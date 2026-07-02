# Is a unit in the right file. A function couples to its own file when it references the
# file's other top-level names, and to another file when its references resolve there
# through the corpus graph. A unit that couples more to one other file than to its own
# has feature envy: it belongs in that file. The neighbourhood the graph's communities
# draw is the deciding gate, the envy ratio the score, both scores in the cohesion
# mould: an absolute band and the corpus percentile, fired when either trips.

# Absolute band on the envy percent: the share of a unit's whole coupling, own-file and
# cross-file, that lands in the single other file it leans toward most. Above 60 a unit
# leans out of its file; above 80 nearly all its coupling is to one other file, feature
# envy with little left at home. A coordinator that reaches into several files spreads
# its mass and stays below the band. Set above an idiomatic spread, like the cohesion
# band; the percentile carries the corpus-relative signal.
const MISPLACED_BAND = (60, 80)

# A unit needs at least this much cross-file reference mass before envy is meaningful:
# one stray call to another file is not a reason to move.
const MIN_MISPLACED_REFS = 3

# The scored candidate set needs this many entries before the envy percentile means
# anything; under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_MISPLACED_FILES = 5

# A unit's own-file affinity: how many of its references resolve, in-file, to a
# definition outside the unit, another function, a file-local type or const. Local
# variables bind inside the unit and are excluded; they say nothing about where the unit
# belongs. Read from the lexical bindings, keyed by graph unit index.
function own_affinity(files::Vector{ParsedFile}, graph::CorpusGraph)
    n = length(files)
    partials = Vector{Dict{Int, Float64}}(undef, n)
    parallel_map!(i -> file_own_affinity(files[i], graph), partials)
    own = Dict{Int, Float64}()
    for i in 1:n
        merge!(own, partials[i])
    end
    return own
end

# One file's unit-to-own-file coupling, keyed by graph unit index. Each file's units carry
# distinct indices, so the per-file maps merge without collision. Read-only over the graph.
function file_own_affinity(f::ParsedFile, graph::CorpusGraph)
    own = Dict{Int, Float64}()
    units = f.index.functions
    isempty(units) && return own
    ranges = Tuple{Int, Int}[TreeSitter.byte_range(u.node) for u in units]
    for (refid, defid) in f.index.bindings
        ur = containing_unit(ranges, refid[1], refid[2])
        ur == 0 && continue
        containing_unit(ranges, defid[1], defid[2]) == ur && continue
        gi = get(graph.unit_index, (f.file, ur), 0)
        gi == 0 && continue
        own[gi] = get(own, gi, 0.0) + 1.0
    end
    return own
end

# The key carrying the greatest value, ties broken by sorted key order so the choice is
# deterministic. Returns `nothing` for an empty mapping.
function dominant(counts::Dict{K}) where {K}
    best, best_val = nothing, nothing
    for k in sort!(collect(keys(counts)))
        v = counts[k]
        (best_val === nothing || v > best_val) && (best = k; best_val = v)
    end
    return best
end

# The file holding the most units in each community: the module the neighbourhood is
# anchored in. A unit whose community is anchored in another file is one the graph would
# move there.
function community_plurality(graph::CorpusGraph, comm::Vector{Int})
    counts = Dict{Int, Dict{String, Int}}()
    for (i, c) in enumerate(comm)
        files = get!(() -> Dict{String, Int}(), counts, c)
        files[graph.units[i].file] = get(files, graph.units[i].file, 0) + 1
    end
    return Dict{Int, String}(c => dominant(files) for (c, files) in counts)
end

# The location to point at in the target file: the unit there the source unit references
# most, or, when its envy is toward a type or const rather than a unit, the first
# definition the symbol table holds for that file.
function target_location(graph::CorpusGraph, table::SymbolTable, src::Int, file::String)
    best_w, best = 0.0, 0
    for ((s, d), w) in graph.edges
        s == src || continue
        graph.units[d].file == file || continue
        w > best_w && (best_w = w; best = d)
    end
    if best != 0
        u = graph.units[best]
        return Location(file, u.line, u.name)
    end
    for d in table.defs
        d.file == file && return Location(file, d.line, d.name)
    end
    return Location(file, 0, "")
end

"""
    cluster_misplaced(files, graph, table; band=$MISPLACED_BAND, cut=0.95, min_files=$MIN_MISPLACED_FILES, min_refs=$MIN_MISPLACED_REFS) -> Vector{Finding}

Units that couple more to another file than to their own, reported as `:misplaced`. The
score is the envy percent, the share of a unit's coupling landing in the one other file
it leans toward most; the finding's first location is the unit, its second the suggested
home. A unit is a candidate only when its cross-file mass clears `min_refs` and its
graph community is anchored in a file other than its own. Each finding carries the
absolute `band` and the corpus percentile, fired when either trips.
"""
function cluster_misplaced(
        files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable;
        band::Tuple{Int, Int} = MISPLACED_BAND, cut::Real = 0.95,
        min_files::Integer = MIN_MISPLACED_FILES, min_refs::Real = MIN_MISPLACED_REFS
    )
    findings = Finding[]
    own = own_affinity(files, graph)
    comm = communities(graph)
    plurality = community_plurality(graph, comm)
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)

    scored = Tuple{Int, Int, Location}[]
    for (src, mass) in graph.file_mass
        total = sum(values(mass))
        total >= min_refs || continue
        target = dominant(mass)
        target === nothing && continue
        best = mass[target]
        unit = graph.units[src]
        plurality[comm[src]] == unit.file && continue
        envy = best / (get(own, src, 0.0) + total)
        score = round(Int, 100 * envy)
        push!(scored, (src, score, target_location(graph, table, src, target)))
    end
    isempty(scored) && return findings

    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (src, score, target) in scored
        absolute = severity(score, band)
        pct = enough ? searchsortedlast(counts, score) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        unit = graph.units[src]
        locations = [Location(unit.file, unit.line, unit.name), target]
        sup = is_suppressed(get(() -> Directive[], directives, unit.file), unit.line, RELATIONAL.misplaced)
        push!(findings, Finding(RELATIONAL.misplaced, locations, score, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
