# The corpus unit graph. Each function across the corpus is a node; a cross-file
# reference, resolved through linkage against the corpus symbol table, is a weighted
# edge. The graph the placement metrics read: feature envy from where a unit's
# reference mass lands, neighbourhoods from the communities the edges form. Name-based
# and lexical throughout, never typed.

# One function unit somewhere in the corpus: its file, the index into that file's unit
# list, its name, and its first line.
struct CorpusUnit
    file::String
    unit::Int
    name::String
    line::Int
end

# Units, the directed weighted edges between them, and per source unit the reference
# mass landing in each target file. `unit_index` maps a `(file, unit)` pair to its node.
# Edges drive community detection; `file_mass` drives the envy score, and carries mass
# to a target even when the target definition is a type or const outside any unit.
struct CorpusGraph
    units::Vector{CorpusUnit}
    unit_index::Dict{Tuple{String, Int}, Int}
    edges::Dict{Tuple{Int, Int}, Float64}
    file_mass::Dict{Int, Dict{String, Float64}}
end

# A definition referenced from more than this fraction of the corpus's units is
# cross-cutting, infrastructure every concern reaches for rather than a placement pull,
# the corpus analog of `COHESION_UBIQUITY`. Edges to it are dropped, so a unit is not
# judged to belong wherever a shared helper happens to live, and communities are not
# collapsed by hub nodes. A floor keeps a small corpus from marking ordinary names as
# cross-cutting.
const CORPUS_UBIQUITY = 0.05
const CORPUS_UBIQUITY_FLOOR = 3

"""
    build_corpus_graph(files, table) -> CorpusGraph

Resolve every cross-file reference in `files` against `table` and record it as a
weighted edge. A reference matching `k` visible definitions splits its weight `1/k`
across them, so each reference contributes mass 1 regardless of how many same-named
definitions it could mean, and a large file does not dominate by holding more
overloads. Visibility comes from [`visible_defs`](@ref): a reference reaches only the
names its file's linkage exposes. References to a cross-cutting definition, one many
units reach for, are dropped so a shared helper does not pull a unit toward its file.
"""
function build_corpus_graph(files::Vector{ParsedFile}, table::SymbolTable)
    corpus = Set{String}(f.file for f in files)
    visible = visible_defs(files, table, corpus)

    units = CorpusUnit[]
    unit_index = Dict{Tuple{String, Int}, Int}()
    for f in files
        for (u, fu) in enumerate(f.index.functions)
            push!(units, CorpusUnit(f.file, u, unit_name(fu, f.index), fu.firstline))
            unit_index[(f.file, u)] = length(units)
        end
    end

    # Resolve references first, counting the distinct units that reach each definition,
    # so cross-cutting names can be dropped before the weighted edges are built.
    resolved = Tuple{Int, Vector{Int}}[]
    breadth = Dict{Int, Set{Int}}()
    for f in files
        names = visible[f.file]
        for ref in unbound_references(f)
            ref.unit == 0 && continue
            candidates = get(names, ref.name, nothing)
            candidates === nothing && continue
            src = unit_index[(f.file, ref.unit)]
            push!(resolved, (src, candidates))
            for di in candidates
                push!(get!(() -> Set{Int}(), breadth, di), src)
            end
        end
    end
    threshold = max(CORPUS_UBIQUITY_FLOOR, ceil(Int, CORPUS_UBIQUITY * length(units)))
    utility = Set{Int}(di for (di, srcs) in breadth if length(srcs) > threshold)

    edges = Dict{Tuple{Int, Int}, Float64}()
    file_mass = Dict{Int, Dict{String, Float64}}()
    for (src, candidates) in resolved
        keep = Int[di for di in candidates if !(di in utility)]
        isempty(keep) && continue
        weight = 1.0 / length(keep)
        mass = get!(() -> Dict{String, Float64}(), file_mass, src)
        for di in keep
            d = table.defs[di]
            mass[d.file] = get(mass, d.file, 0.0) + weight
            d.unit == 0 && continue
            dst = get(unit_index, (d.file, d.unit), 0)
            dst == 0 && continue
            edges[(src, dst)] = get(edges, (src, dst), 0.0) + weight
        end
    end
    return CorpusGraph(units, unit_index, edges, file_mass)
end

# Undirected weighted adjacency over the units: a coupling is mutual, so a directed
# edge and its reverse fold into one neighbour weight. Self-loops cannot arise, since a
# cross-file edge always joins units in different files.
function adjacency(graph::CorpusGraph)
    n = length(graph.units)
    adj = [Dict{Int, Float64}() for _ in 1:n]
    for ((a, b), w) in graph.edges
        adj[a][b] = get(adj[a], b, 0.0) + w
        adj[b][a] = get(adj[b], a, 0.0) + w
    end
    return adj
end

"""
    communities(graph) -> Vector{Int}

A community label per unit, from one level of modularity optimisation (Louvain local
moving) over the undirected unit graph. Units that couple end up in one community, the
module the references say they belong to; a unit with no cross-file edge is its own
community. Labels are contiguous from 1, assigned in first-seen order for determinism.
"""
communities(graph::CorpusGraph) = communities(adjacency(graph))

# The community labels for a prebuilt undirected adjacency, the shape `:scattered`
# reuses with within-file edges folded in.
function communities(adj::Vector{Dict{Int, Float64}})
    n = length(adj)
    degree = Float64[sum(values(adj[i]); init = 0.0) for i in 1:n]
    twom = sum(degree)
    comm = collect(1:n)
    twom == 0 && return relabel(comm)
    total = copy(degree)
    improved = true
    while improved
        improved = false
        for i in 1:n
            ci = comm[i]
            ki = degree[i]
            total[ci] -= ki
            weight_to = Dict{Int, Float64}()
            for (j, w) in adj[i]
                j == i && continue
                weight_to[comm[j]] = get(weight_to, comm[j], 0.0) + w
            end
            best = ci
            best_gain = get(weight_to, ci, 0.0) - total[ci] * ki / twom
            for c in sort!(collect(keys(weight_to)))
                gain = weight_to[c] - total[c] * ki / twom
                gain > best_gain + 1.0e-12 && (best = c; best_gain = gain)
            end
            total[best] += ki
            if best != ci
                comm[i] = best
                improved = true
            end
        end
    end
    return relabel(comm)
end

# Renumber community labels to a contiguous 1..K in first-seen order, so the result
# does not depend on the internal node ids the optimiser happened to settle on.
function relabel(comm::Vector{Int})
    seen = Dict{Int, Int}()
    out = similar(comm)
    for (i, c) in enumerate(comm)
        out[i] = get!(seen, c, length(seen) + 1)
    end
    return out
end
