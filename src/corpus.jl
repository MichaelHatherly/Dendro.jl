# Cross-corpus duplicate detection. A separate pass from the per-file pipeline:
# it walks many files, hashes each function's structure, and reports functions
# that share a shape. This crosses Dendro's single-file boundary but stays inside
# the syntactic bargain, no symbol resolution, just node-type sequences.

# Default minimum unit size, in named nodes, for a function to be considered.
# Below this a function is too small to make a meaningful duplicate, a one-line
# getter is a handful of nodes; a real function clears this comfortably.
const DEFAULT_MIN_SIZE = 10

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

"""
    analyze_corpus(paths; min_size=$DEFAULT_MIN_SIZE, language=nothing) -> Vector{Finding}

Find functions duplicated across `paths`, including across different files,
tolerant to identifier renaming and literal-value changes. Returns one
`:duplicate` [`Finding`](@ref) per cluster of at least two functions whose
canonical size is at least `min_size` named nodes, its `locations` listing every
member. A cluster is suppressed when any member carries a `dendro-ignore:
duplicate` directive. Files whose language has no profile are skipped. Pass
`language` to force one language for every path, as [`analyze`](@ref) does.
"""
function analyze_corpus(paths; min_size::Integer = DEFAULT_MIN_SIZE, language = nothing)
    forced = language === nothing ? nothing : Symbol(lowercase(String(language)))
    groups = Dict{Tuple{Symbol,UInt64},Vector{Tuple{Location,Bool}}}()
    parsers = Dict{Symbol,TreeSitter.Parser}()
    for path in paths
        lang = forced === nothing ? language_for_path(path) : forced
        (lang === nothing || !haskey(PROFILES, lang)) && continue
        profile = PROFILES[lang]
        parser = get!(() -> parser_for(lang), parsers, lang)
        source = read(path, String)
        tree = parse(parser, source)
        directives = suppressions(tree, profile, source; file = path)
        for unit in functions(tree, profile)
            digest, size = structural_digest(unit, profile)
            size < min_size && continue
            loc = Location(String(path), unit.firstline, unit_name(unit, profile, source))
            sup = is_suppressed(directives, unit.firstline, :duplicate)
            push!(get!(() -> Tuple{Location,Bool}[], groups, (lang, digest)), (loc, sup))
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
