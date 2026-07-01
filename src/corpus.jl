# Corpus analysis. The per-file pipeline scores one file; this scores a whole
# project, building the baseline from the corpus and adding cross-file duplicate
# detection (exact and near, defined in `clones.jl`). Detection crosses the
# single-file boundary but stays inside the syntactic bargain, no symbol
# resolution, just node types and tree shape.

# Parse each path once. Each record carries everything the baseline, the per-file
# scoring pass, and duplicate clustering need, so no file is parsed twice. Files
# whose language has no profile are skipped. `language` forces one language for
# every path, as `analyze` does.
function parse_corpus(paths::AbstractVector{<:AbstractString}; language = nothing, rules = BUILTIN_RULES)
    forced = language === nothing ? nothing : Symbol(lowercase(String(language)))
    entries = Tuple{String, Symbol}[]
    for path in paths
        lang = forced === nothing ? language_for_path(path) : forced
        lang === nothing && continue
        haskey(PROFILES, lang) || continue
        push!(entries, (String(path), lang))
    end
    n = length(entries)
    files = Vector{ParsedFile}(undef, n)
    # Warm every language's caches single-threaded before the parallel parse first-touches
    # them; this also leaves the imports query warm for the linkage passes downstream.
    parallel_enabled(n) && warm_languages(unique(last(e) for e in entries))
    parallel_chunks(n) do _, idxs
        parse_chunk!(files, entries, idxs, rules)
    end
    return files
end

# Parse one chunk of files with a task-local parser pool: a `TreeSitter.Parser` is stateful,
# so each chunk keeps its own, reused across its files. Writes into the shared preallocated
# `files` at each entry's index, so the corpus order matches the serial path.
function parse_chunk!(files::Vector{ParsedFile}, entries::Vector{Tuple{String, Symbol}}, idxs, rules)
    parsers = Dict{Symbol, TreeSitter.Parser}()
    for i in idxs
        path, lang = entries[i]
        parser = get!(() -> parser_for(lang), parsers, lang)
        source = read(path, String)
        tree = parse(parser, source)
        index = build_index(tree, lang, source, query_for(lang), scopes_query_for(lang))
        directives = suppressions(index; file = path, rules)
        files[i] = ParsedFile(lang, source, path, tree, index, directives)
    end
    return nothing
end

# Baseline over already-parsed corpus records. Each chunk samples into its own partial
# baseline; the merge concatenates per `(language, metric)` and the final `sort!` fixes the
# order, so the sorted samples are identical to the serial path at any thread count.
function baseline_from(files::Vector{ParsedFile}, rules = BUILTIN_RULES)
    n = length(files)
    partials = [Baseline() for _ in 1:n_chunks(n)]
    parallel_chunks(n) do c, idxs
        sample_chunk!(partials[c], files, idxs, rules)
    end
    baseline = merge_baselines(partials)
    for samples in values(baseline.samples)
        sort!(samples)
    end
    return baseline
end

# Sample one chunk of files into a partial baseline.
function sample_chunk!(baseline::Baseline, files::Vector{ParsedFile}, idxs, rules)
    for i in idxs
        add_samples!(baseline, files[i].index, rules)
    end
    return baseline
end

# Concatenate partial baselines per `(language, metric)`. The caller sorts the merged
# samples, so the append order does not affect the result.
function merge_baselines(partials::Vector{Baseline})
    merged = Baseline()
    for p in partials
        for (k, v) in p.samples
            append!(get!(() -> Float64[], merged.samples, k), v)
        end
    end
    return merged
end

# The git toplevel containing the first of `paths`, found from that path's directory.
# The repo root the diff scope and the ratchet base both resolve their relative paths
# against.
function git_toplevel(paths::Union{AbstractString, AbstractVector{<:AbstractString}})
    ref = paths isa AbstractString ? paths : first(paths)
    dir = isdir(ref) ? ref : dirname(ref)
    return String(strip(read(pipeline(`git -C $dir rev-parse --show-toplevel`; stderr = devnull), String)))
end

# A diff scope: the git toplevel and the changed line ranges per file, relative to
# that root. Mirrors the per-file shape `changed_ranges` returns.
struct Scope
    root::String
    ranges::Dict{String, Vector{UnitRange{Int}}}
end

# Keep only cluster findings touching a changed line, the diff-scoped view shared
# by exact and near-miss duplicates. Without a scope every cluster passes through.
function scope_clusters(clusters::Vector{Finding}, scope::Union{Scope, Nothing})
    scope === nothing && return clusters
    return filter(clusters) do c
        any(c.locations) do loc
            rel = relpath(realpath(loc.file), scope.root)
            haskey(scope.ranges, rel) && inrange(scope.ranges[rel], loc.line)
        end
    end
end

# Recurse a directory for files Dendro can analyze, pruning dot-directories like
# `.git` and keeping only files whose extension resolves to a language profile.
# `ignore` patterns, matched against each path relative to `dir`, prune directories
# and drop files before they reach the corpus, so vendored source never feeds the
# baseline.
function source_files(dir::AbstractString, ignore = String[])
    patterns = compile_ignores(ignore)
    files = String[]
    for (root, dirs, names) in walkdir(dir)
        filter!(dirs) do d
            !startswith(d, ".") && !is_ignored(patterns, relpath(joinpath(root, d), dir), true)
        end
        for name in names
            lang = language_for_path(name)
            (lang === nothing || !haskey(PROFILES, lang)) && continue
            is_ignored(patterns, relpath(joinpath(root, name), dir), false) && continue
            push!(files, joinpath(root, name))
        end
    end
    return files
end

# Resolve a list of roots into the unique set of file paths to parse. A directory is
# walked for analyzable source under `ignore`; a named file is taken as-is, but only
# when its language can be inferred or `language` forces one. The shared front of
# `analyze` and `mermaid`, so both see the same corpus from the same roots.
function collect_corpus(roots::Vector{String}, ignore, language)
    isempty(roots) && error("Dendro: no paths given")
    corpus = String[]
    for path in roots
        ispath(path) || error("Dendro: no such path $path")
        if isdir(path)
            append!(corpus, source_files(path, ignore))
        else
            language === nothing && language_for_path(path) === nothing &&
                error("Dendro: cannot infer language for $path; pass `language=`.")
            push!(corpus, path)
        end
    end
    unique!(corpus)
    return corpus
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
    cfg::Config = config === nothing ? discover_config(roots) : config
    ecut = cut === nothing ? cfg.cut : Float64(cut)
    active_rules = rules === nothing ? resolve_rules(cfg) : collect(Rule, rules)
    msize = min_size === nothing ? cfg.min_size : Int(min_size)
    thresh = threshold === nothing ? cfg.threshold : Float64(threshold)
    radius = radius_factor === nothing ? cfg.radius_factor : Float64(radius_factor)

    corpus = collect_corpus(roots, ignore, language)
    files = parse_corpus(corpus; language, rules = active_rules)
    bl = baseline_from(files, active_rules)

    scope::Union{Scope, Nothing} = nothing
    if base !== nothing
        root = git_toplevel(roots)
        scope = Scope(root, changed_ranges(read(`git -C $root diff $base`, String)))
    end

    perfile = Vector{Vector{Finding}}(undef, length(files))
    parallel_map!(perfile, length(files)) do i
        f = files[i]
        within = nothing
        if scope !== nothing
            rel = relpath(realpath(f.file), scope.root)
            haskey(scope.ranges, rel) || return Finding[]
            within = scope.ranges[rel]
        end
        scan = Scan(f.index, f.file; rules = active_rules, baseline = bl, cut = ecut, within = within, directives = f.directives)
        findings_for(scan)
    end
    findings = Finding[]
    for pf in perfile
        append!(findings, pf)
    end

    append!(findings, scope_clusters(cluster_duplicates(files; min_size = msize), scope))
    append!(
        findings, scope_clusters(
            cluster_near_duplicates(files; min_size = msize, threshold = thresh, radius_factor = radius), scope
        )
    )
    append!(findings, scope_clusters(cluster_unnatural(files; cut = ecut, band = cfg.unnatural), scope))

    table = corpus_symbols(files)
    graph = build_corpus_graph(files, table)
    append!(findings, scope_clusters(cluster_low_cohesion(files, graph; cut = ecut, band = cfg.low_cohesion), scope))
    append!(findings, scope_clusters(cluster_misplaced(files, graph, table; cut = ecut, band = cfg.misplaced), scope))
    append!(findings, scope_clusters(cluster_scattered(files, graph; cut = ecut, band = cfg.scattered), scope))
    append!(findings, scope_clusters(cluster_unreferenced(files, table), scope))
    return Findings(findings)
end
