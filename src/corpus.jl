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
    parsers = Dict{Symbol, TreeSitter.Parser}()
    files = ParsedFile[]
    for path in paths
        lang = forced === nothing ? language_for_path(path) : forced
        (lang === nothing || !haskey(PROFILES, lang)) && continue
        profile = PROFILES[lang]
        parser = get!(() -> parser_for(lang), parsers, lang)
        source = read(path, String)
        tree = parse(parser, source)
        directives = suppressions(tree, profile, source; file = path, rules)
        push!(files, ParsedFile(lang, profile, source, String(path), tree, directives))
    end
    return files
end

# Baseline over already-parsed corpus records.
function baseline_from(files::AbstractVector{ParsedFile}, rules = BUILTIN_RULES)
    baseline = Baseline()
    for f in files
        add_samples!(baseline, f.language, f.tree, f.profile, f.source, rules)
    end
    for samples in values(baseline.samples)
        sort!(samples)
    end
    return baseline
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

"""
    analyze(path; base=nothing, cut=0.95, min_size=$DEFAULT_MIN_SIZE, threshold=$DEFAULT_THRESHOLD, language=nothing, rules=BUILTIN_RULES) -> Findings

Analyze the file or folder at `path`. Every function gets scalar and flag metrics;
functions duplicated across the corpus are reported as `:duplicate` findings, and
functions that are close but not identical as `:near_duplicate`. A baseline is built
from the corpus, the folder's files or the single file, so relative scoring works
against the input's own distribution with no setup. With `base`, only functions
changed against that git ref are reported, scored against the full-corpus baseline.

`threshold` is the Dice cutoff for a near-miss, `radius_factor` scales the
candidate-search radius to a function's size.

`rules` is the active rule set, defaulting to [`BUILTIN_RULES`]. Append your own
[`Rule`](@ref)s to lint for a project's structural conventions:
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
        path::AbstractString; base = nothing, cut::Real = 0.95,
        min_size::Integer = DEFAULT_MIN_SIZE,
        threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR, language = nothing,
        rules = BUILTIN_RULES, ignore = String[]
    )
    ispath(path) || error("Dendro: no such path $path")
    if isdir(path)
        corpus = source_files(path, ignore)
    else
        language === nothing && language_for_path(path) === nothing &&
            error("Dendro: cannot infer language for $path; pass `language=`.")
        corpus = [path]
    end
    files = parse_corpus(corpus; language, rules)
    bl = baseline_from(files, rules)

    scope::Union{Scope, Nothing} = nothing
    if base !== nothing
        root = String(strip(read(`git -C $(isdir(path) ? path : dirname(path)) rev-parse --show-toplevel`, String)))
        scope = Scope(root, changed_ranges(read(`git -C $root diff $base`, String)))
    end

    findings = Finding[]
    for f in files
        within = nothing
        if scope !== nothing
            rel = relpath(realpath(f.file), scope.root)
            haskey(scope.ranges, rel) || continue
            within = scope.ranges[rel]
        end
        scan = Scan(f.profile, f.source, f.file; rules, baseline = bl, cut = cut, within = within, directives = f.directives)
        append!(findings, findings_for_tree(f.tree, scan))
    end

    append!(findings, scope_clusters(cluster_duplicates(files; min_size), scope))
    append!(
        findings, scope_clusters(
            cluster_near_duplicates(files; min_size, threshold, radius_factor), scope
        )
    )
    append!(findings, scope_clusters(cluster_unnatural(files; cut), scope))
    return Findings(findings)
end
