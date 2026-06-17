# Corpus analysis. The per-file pipeline scores one file; this scores a whole
# project, building the baseline from the corpus and adding cross-file duplicate
# detection. Duplicate detection crosses the single-file boundary but stays inside
# the syntactic bargain, no symbol resolution, just node-type sequences.

# Default minimum unit size, in named nodes, for a function to be considered a
# possible duplicate. Below this a function is too small to make a meaningful
# clone, a one-line getter is a handful of nodes; a real function clears it.
const DEFAULT_MIN_SIZE = 10

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

"""
    structural_digest(unit, profile) -> (UInt64, Int)

Hash a function unit by the enter-order sequence of its named node types,
hashing the type and never the text, so functions that differ only in identifier
names or literal values share a digest (Type-2 clones). Nested callables are not
descended into. Returns the digest and the count of named nodes, the size used to
gate trivial units.
"""
function structural_digest(unit::FunctionUnit, profile::LanguageProfile)
    h = hash(:dendro_clone)
    n = 0
    traverse_unit(unit.node, profile) do node, enter
        if enter && TreeSitter.is_named(node)
            h = hash(TreeSitter.node_type(node), h)
            n += 1
        end
        nothing
    end
    return h, n
end

# Cluster the corpus records' functions by structural digest, keyed by language
# so shapes never collide across languages. Each cluster of two or more above the
# size gate becomes one `:duplicate` finding, suppressed when any member carries a
# `dendro-ignore: duplicate` directive.
function cluster_duplicates(files; min_size::Integer = DEFAULT_MIN_SIZE)
    groups = Dict{Tuple{Symbol,UInt64},Vector{Tuple{Location,Bool}}}()
    for f in files
        for unit in functions(f.tree, f.profile)
            digest, size = structural_digest(unit, f.profile)
            size < min_size && continue
            loc = Location(f.file, unit.firstline, unit_name(unit, f.profile, f.source))
            sup = is_suppressed(f.directives, unit.firstline, :duplicate)
            push!(get!(() -> Tuple{Location,Bool}[], groups, (f.language, digest)), (loc, sup))
        end
    end
    findings = Finding[]
    for members in values(groups)
        length(members) < 2 && continue
        locations = [loc for (loc, _) in members]
        suppressed = any(sup for (_, sup) in members)
        push!(findings, Finding(:duplicate, locations, length(locations), :high, nothing, :flag, suppressed))
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end

"""
    find_duplicates(paths; min_size=$DEFAULT_MIN_SIZE, language=nothing) -> Vector{Finding}

Find functions duplicated across `paths`, including across different files,
tolerant to identifier renaming and literal-value changes (Type-2 clones).
Returns one `:duplicate` [`Finding`](@ref) per cluster of at least two functions
whose canonical size is at least `min_size` named nodes, its `locations` listing
every member. Files whose language has no profile are skipped. Pass `language` to
force one language for every path.
"""
find_duplicates(paths; min_size::Integer = DEFAULT_MIN_SIZE, language = nothing) =
    cluster_duplicates(parse_corpus(paths; language); min_size = min_size)

"""
    analyze_corpus(paths; min_size=$DEFAULT_MIN_SIZE, language=nothing, baseline=nothing, cut=0.95) -> Vector{Finding}

Analyze every file in `paths`: per-function scalar and flag metrics for each,
scored against a `baseline`, plus cross-file duplicates (see
[`find_duplicates`](@ref)). With no `baseline`, one is built from `paths`, so
relative scoring works against the corpus's own distribution with no setup. Pass a
`baseline` to score `paths` against a wider corpus. Per-file findings come first in
path order, duplicates last. Files whose language has no profile are skipped.
"""
function analyze_corpus(paths; min_size::Integer = DEFAULT_MIN_SIZE, language = nothing,
                        baseline = nothing, cut::Real = 0.95)
    files = parse_corpus(paths; language)
    bl = baseline === nothing ? baseline_from(files) : baseline
    findings = Finding[]
    for f in files
        scan = Scan(f.profile, f.source, f.file; baseline = bl, cut = cut, directives = f.directives)
        append!(findings, findings_for_tree(f.tree, scan))
    end
    append!(findings, cluster_duplicates(files; min_size = min_size))
    return findings
end
