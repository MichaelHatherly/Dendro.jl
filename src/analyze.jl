# The analysis entry point. `corpus.jl` gathers and parses the files; this drives the
# passes over them and assembles the result. The diff scope lives here too, since it is
# `analyze`'s framing of the question rather than a property of the corpus.

# The git toplevel containing the first of `paths`, found from that path's directory.
# The repo root the diff scope and the ratchet base both resolve their relative paths
# against.
function git_toplevel(paths::Union{AbstractString, AbstractVector{<:AbstractString}})
    ref = paths isa AbstractString ? paths : first(paths)
    dir = isdir(ref) ? ref : dirname(ref)
    return String(strip(read(pipeline(`git -C $dir rev-parse --show-toplevel`; stderr = devnull), String)))
end

# A diff scope: the git toplevel, the changed line ranges per file relative to that root,
# and each corpus file's path already resolved against it. Mirrors the per-file shape
# `changed_ranges` returns.
#
# `rels` is resolved up front over the whole corpus rather than per location. Every scoping
# test needs a location's repo-relative path, `realpath` is a syscall, and a dozen passes
# scope their findings against one `Scope`, so the same file would otherwise be resolved
# once per location per pass. Building it before the per-file scan also keeps it read-only,
# which is what lets the parallel pass share it without a lock.
struct Scope
    root::String
    ranges::Dict{String, Vector{UnitRange{Int}}}
    rels::Dict{String, String}
end

Scope(root::String, ranges::Dict{String, Vector{UnitRange{Int}}}, files::Vector{ParsedFile}) =
    Scope(root, ranges, Dict{String, String}(f.file => relpath(realpath(f.file), root) for f in files))

# Whether one location sits on a changed line. Every path a finding names is a corpus file,
# so a miss here is a finding built from a path the scan never parsed, which is a bug to
# surface rather than to read as out of scope.
in_scope(scope::Scope, loc::Location) =
    (rel = scope.rels[loc.file]; haskey(scope.ranges, rel) && inrange(scope.ranges[rel], loc.line))

# Keep only cluster findings touching a changed line, the diff-scoped view shared
# by exact and near-miss duplicates. Without a scope every cluster passes through.
function scope_clusters(clusters::Vector{Finding}, scope::Union{Scope, Nothing})
    scope === nothing && return clusters
    return filter(c -> any(loc -> in_scope(scope, loc), c.locations), clusters)
end

"""
    CorpusResolution

Everything the passes past a single file share: the symbol `table`, the `linkage` resolving
the corpus against itself, the filtered `unit_graph` the placement rules read, and the
unfiltered `file_graph` the architecture rules read. Built once by [`resolve_corpus`](@ref),
since resolving a corpus is among the most expensive steps in a scan and six passes want the
same answer.
"""
struct CorpusResolution
    table::SymbolTable
    linkage::ResolvedLinkage
    unit_graph::CorpusGraph
    file_graph::FileGraph
end

"""
    resolve_corpus(files) -> CorpusResolution

Resolve `files` against each other once: the symbol table, the linkage over it, and the two
graphs over that. The file graph keeps the references the unit graph drops as cross-cutting,
since a definition everything reaches for is what an architecture question is about, where
placement needs it discounted.
"""
function resolve_corpus(files::Vector{ParsedFile})
    table = corpus_symbols(files)
    linkage = resolve_linkage(files, table)
    return CorpusResolution(
        table, linkage,
        build_corpus_graph(files, table; linkage),
        build_file_graph(files, table, linkage.corpus; linkage),
    )
end

# Every clone pass, scoped and ranked by how far apart a cluster's members sit in the module
# graph. The opt-in vocabulary pass is gated here rather than resolved into the rule set,
# and reads the unscoped clone findings: a pair is excluded because the structural passes
# reported it at all, not because the diff kept it.
function clone_clusters(files::Vector{ParsedFile}, cfg::Config, scope, placement::ModulePlacement)
    exact = rank_clones!(cluster_duplicates(files; min_size = cfg.min_size), placement)
    near = rank_clones!(
        cluster_near_duplicates(
            files; min_size = cfg.min_size, threshold = cfg.threshold,
            radius_factor = cfg.radius_factor
        ), placement
    )
    findings = [scope_clusters(exact, scope); scope_clusters(near, scope)]
    get(cfg.rules, RELATIONAL.reimplementation, false) || return findings
    reimpl = cluster_reimplementations(
        files; min_size = cfg.min_size, threshold = cfg.reimpl_threshold,
        clone_findings = [exact; near]
    )
    append!(findings, scope_clusters(rank_clones!(reimpl, placement), scope))
    return findings
end

# Every corpus-relational pass, scoped, in the order a report reads them. The opt-in
# directory pass is gated here for the same reason the vocabulary one is: it proposes a
# rearrangement rather than a bounded edit, so it stays out of the default set and out of
# the gate floor.
function relational_clusters(files::Vector{ParsedFile}, cfg::Config, scope, res::CorpusResolution)
    ecut = cfg.cut
    table, linkage = res.table, res.linkage
    graph, fg = res.unit_graph, res.file_graph
    findings = scope_clusters(cluster_unnatural(files; cut = ecut, band = cfg.unnatural), scope)
    append!(findings, scope_clusters(cluster_low_cohesion(files, graph; cut = ecut, band = cfg.low_cohesion), scope))
    append!(findings, scope_clusters(cluster_misplaced(files, graph, table; cut = ecut, band = cfg.misplaced), scope))
    append!(findings, scope_clusters(cluster_scattered(files, graph; cut = ecut, band = cfg.scattered), scope))
    append!(findings, scope_clusters(cluster_unreferenced(files, table; linkage), scope))
    append!(
        findings,
        scope_clusters(cluster_split_audience(files, table; cut = ecut, band = cfg.split_audience, linkage), scope)
    )
    if get(cfg.rules, RELATIONAL.incoherent_package, false)
        append!(
            findings,
            scope_clusters(
                cluster_incoherent_packages(files, graph; cut = ecut, band = cfg.incoherent_package), scope
            )
        )
    end
    append!(findings, scope_clusters(cluster_back_edge(files, fg, table; cut = ecut, band = cfg.back_edge, linkage), scope))
    append!(
        findings,
        scope_clusters(cluster_dependency_cycles(files, fg; cut = ecut, band = cfg.dependency_cycle), scope)
    )
    append!(findings, scope_clusters(cluster_hub(files, fg, table; linkage, cut = ecut, band = cfg.hub), scope))
    return findings
end

"""
    analyze(path; base=nothing, cut=nothing, min_size=nothing, threshold=nothing, radius_factor=nothing, language=nothing, rules=nothing, ignore=String[], config=nothing) -> Findings
    analyze(paths::AbstractVector; ...) -> Findings

Analyze the file or folder at `path`. Every function gets scalar and flag metrics;
functions duplicated across the corpus are reported as `:duplicate` findings, and
functions that are close but not identical as `:near_duplicate`. A baseline is built
from the corpus, the folder's files or the single file, so relative scoring works
against the input's own distribution with no setup. With `base`, only functions
changed against that git ref are reported, scored against the full-corpus baseline.

Passing several paths folds their files into one corpus, so a package's `src` and
`ext` are scanned together (`analyze(["src", "ext"])`) without dragging in the rest
of the tree. The baseline, duplicate detection, and naturalness span the roots, so
a function copied from one into another is caught. With `base`, all roots resolve
to the one git toplevel and the repo-wide diff scopes them.

`threshold` is the LCS-similarity cutoff for a near-miss, `radius_factor` scales the
candidate-search radius to a function's size.

The `:reimplementation` pass, vocabulary-overlap pairs the structural passes miss, is
off by default and enabled only through the config, `[rules] reimplementation = true`
in a `.dendro.toml` or a `config` built here; the `rules` kwarg carries `Rule`s and
cannot express it. Its overlap cutoff is the config's `[reimplementation] threshold`.

Thresholds come from a [`Config`](@ref): the bands, the percentile `cut`, and which
rules are active. By default `analyze` discovers one, merging a user-global config and
the repo `.dendro.toml` over the built-in defaults.
Pass `config` to supply one directly and skip discovery. An explicit `cut` or `rules`
overrides the config, so a caller keeps the final say.

`cut` is the percentile cutoff a corpus-relative metric flags above; it defaults to
the config's, `0.95` absent a file. `rules` is the active rule set; absent, it is the
config's resolution of [`BUILTIN_RULES`](@ref) and the enabled [`OPTIONAL_RULES`](@ref).
Pass your own to lint for a project's structural conventions:
`analyze(path; rules = [BUILTIN_RULES; my_rule])`.

`ignore` is a list of gitignore-style patterns, matched against each path relative
to a scanned folder. Matching files are dropped before parsing, so vendored or
generated source is neither flagged nor counted in the baseline:
`analyze(path; ignore = ["vendor/", "*.generated.jl"])`. A leading `!` re-includes,
a trailing `/` matches directories only. As in gitignore, a file under an excluded
directory cannot be re-included. Patterns apply to folder scans, not a single named
file.
"""
function analyze(
        paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        base = nothing, cut = nothing,
        min_size = nothing, threshold = nothing, radius_factor = nothing,
        language = nothing, rules = nothing, ignore = String[], config = nothing
    )
    roots::Vector{String} = paths isa AbstractString ? [paths] : paths
    discovered::Config = config === nothing ? discover_config(roots) : config
    cfg = override_config(discovered; cut, min_size, threshold, radius_factor)
    active_rules = rules === nothing ? resolve_rules(cfg) : collect(Rule, rules)

    profiles = resolve_profiles(cfg)
    corpus = collect_corpus(roots, ignore, language; profiles)
    files = parse_corpus(
        corpus; language, rules = active_rules, profiles,
        patterns = cfg.patterns, pattern_dirs = pattern_dirs(cfg, roots)
    )
    bl = baseline_from(files, active_rules)
    # Resolved once for the whole scan: which metrics' distributions support a rank.
    guard = percentile_guard(bl, cfg.cut)

    # Assigned once, so the scoring closure captures it concretely, never as a `Core.Box`.
    scope = if base === nothing
        nothing
    else
        root = git_toplevel(roots)
        Scope(root, changed_ranges(read(`git -C $root diff $base`, String)), files)
    end

    findings = parallel_flatmap(length(files), Finding) do i
        f = files[i]
        within = nothing
        if scope !== nothing
            rel = scope.rels[f.file]
            haskey(scope.ranges, rel) || return Finding[]
            within = scope.ranges[rel]
        end
        scan = Scan(
            f.index, f.file; rules = active_rules, baseline = bl, cut = cfg.cut,
            within = within, directives = f.directives, guard
        )
        findings_for(scan)
    end

    res = resolve_corpus(files)
    append!(findings, clone_clusters(files, cfg, scope, ModulePlacement(res.file_graph)))
    append!(findings, relational_clusters(files, cfg, scope, res))
    return Findings(findings, unmatched_patterns(files, cfg.patterns))
end
