# Corpus analysis. The per-file pipeline scores one file; this scores a whole
# project, building the baseline from the corpus and adding cross-file duplicate
# detection (exact and near, defined in `clones.jl`). Detection crosses the
# single-file boundary but stays inside the syntactic bargain, no symbol
# resolution, just node types and tree shape.

# Parse each path once. Each record carries everything the baseline, the per-file
# scoring pass, and duplicate clustering need, so no file is parsed twice. Files
# whose language has no profile are skipped. `language` forces one language for
# every path, as `analyze` does.
function parse_corpus(paths; language = nothing)
    forced = language === nothing ? nothing : Symbol(lowercase(String(language)))
    parsers = Dict{Symbol,TreeSitter.Parser}()
    files = NamedTuple[]
    for path in paths
        lang = forced === nothing ? language_for_path(path) : forced
        (lang === nothing || !haskey(PROFILES, lang)) && continue
        profile = PROFILES[lang]
        parser = get!(() -> parser_for(lang), parsers, lang)
        source = read(path, String)
        tree = parse(parser, source)
        directives = suppressions(tree, profile, source; file = path)
        push!(files, (language = lang, profile = profile, source = source,
                      file = String(path), tree = tree, directives = directives))
    end
    return files
end

# Baseline over already-parsed corpus records.
function baseline_from(files)
    baseline = Baseline()
    for f in files
        add_samples!(baseline, f.language, f.tree, f.profile, f.source)
    end
    for samples in values(baseline.samples)
        sort!(samples)
    end
    return baseline
end

# Keep only cluster findings touching a changed line, the diff-scoped view shared
# by exact and near-miss duplicates. Without a scope every cluster passes through.
function scope_clusters(clusters, scope)
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
function source_files(dir)
    files = String[]
    for (root, dirs, names) in walkdir(dir)
        filter!(d -> !startswith(d, "."), dirs)
        for name in names
            lang = language_for_path(name)
            (lang === nothing || !haskey(PROFILES, lang)) && continue
            push!(files, joinpath(root, name))
        end
    end
    return files
end

"""
    analyze(path; base=nothing, cut=0.95, min_size=$DEFAULT_MIN_SIZE, threshold=$DEFAULT_THRESHOLD, language=nothing) -> Findings

Analyze the file or folder at `path`. Every function gets scalar and flag metrics;
functions duplicated across the corpus are reported as `:duplicate` findings, and
functions that are close but not identical as `:near_duplicate`. A baseline is built
from the corpus, the folder's files or the single file, so relative scoring works
against the input's own distribution with no setup. With `base`, only functions
changed against that git ref are reported, scored against the full-corpus baseline.

`threshold` is the Dice cutoff for a near-miss, `radius_factor` scales the
candidate-search radius to a function's size.
"""
function analyze(path; base = nothing, cut::Real = 0.95,
                 min_size::Integer = DEFAULT_MIN_SIZE,
                 threshold::Real = DEFAULT_THRESHOLD,
                 radius_factor::Real = DEFAULT_RADIUS_FACTOR, language = nothing)
    ispath(path) || error("Dendro: no such path $path")
    if isdir(path)
        corpus = source_files(path)
    else
        language === nothing && language_for_path(path) === nothing &&
            error("Dendro: cannot infer language for $path; pass `language=`.")
        corpus = [path]
    end
    files = parse_corpus(corpus; language)
    bl = baseline_from(files)

    scope = nothing
    if base !== nothing
        root = strip(read(`git -C $(isdir(path) ? path : dirname(path)) rev-parse --show-toplevel`, String))
        scope = (root = root, ranges = changed_ranges(read(`git -C $root diff $base`, String)))
    end

    findings = Finding[]
    for f in files
        within = nothing
        if scope !== nothing
            rel = relpath(realpath(f.file), scope.root)
            haskey(scope.ranges, rel) || continue
            within = scope.ranges[rel]
        end
        scan = Scan(f.profile, f.source, f.file; baseline = bl, cut = cut, within = within, directives = f.directives)
        append!(findings, findings_for_tree(f.tree, scan))
    end

    append!(findings, scope_clusters(cluster_duplicates(files; min_size), scope))
    append!(findings, scope_clusters(
        cluster_near_duplicates(files; min_size, threshold, radius_factor), scope))
    return Findings(findings)
end
