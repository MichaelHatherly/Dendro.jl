# The corpus unit graph. Each function across the corpus is a node; a cross-file
# reference, resolved through linkage against the corpus symbol table, is a weighted
# `edges` entry, and a within-file binding edge a `within_edges` entry. The graph every
# relational pass reads: feature envy from where a unit's reference mass lands,
# neighbourhoods from the communities the cross-file edges form, and connected components
# from the within-file edges. Each metric is a view of the one graph plus an algorithm.
# Name-based and lexical throughout, never typed.

# One function unit somewhere in the corpus: its file, the index into that file's unit
# list, its name, and its first line.
struct CorpusUnit
    file::String
    unit::Int
    name::String
    line::Int
end

# Units, the directed weighted cross-file edges between them, the within-file binding
# edges, and per source unit the reference mass landing in each target file.
# `unit_index` maps a `(file, unit)` pair to its node. Cross-file `edges` drive community
# detection; `within_edges` join a file's own units so a cohesive file clusters together;
# `file_mass` drives the envy score, and carries mass to a target even when the target
# definition is a type or const outside any unit.
struct CorpusGraph
    units::Vector{CorpusUnit}
    unit_index::Dict{Tuple{String, Int}, Int}
    edges::Dict{Tuple{Int, Int}, Float64}
    within_edges::Dict{Tuple{Int, Int}, Float64}
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
    build_corpus_graph(files, table; within_ubiquity=$COHESION_UBIQUITY) -> CorpusGraph

Resolve every cross-file reference in `files` against `table` and record it as a
weighted edge, and record each file's within-file binding edges. A reference matching
`k` visible definitions splits its weight `1/k` across them, so each reference
contributes mass 1 regardless of how many same-named definitions it could mean, and a
large file does not dominate by holding more overloads. Visibility comes from
[`visible_defs`](@ref): a reference reaches only the names its file's linkage exposes.
References to a cross-cutting definition, one many units reach for, are dropped so a
shared helper does not pull a unit toward its file. The within edges star-link each
[`binding_groups`](@ref) group to its first member, dropping a binding referenced by
more than `within_ubiquity` of a file's units; a language with no scopes query carries
none.
"""
function build_corpus_graph(files::Vector{ParsedFile}, table::SymbolTable; within_ubiquity::Float64 = COHESION_UBIQUITY)
    units = CorpusUnit[]
    unit_index = Dict{Tuple{String, Int}, Int}()
    for f in files
        for (u, fu) in enumerate(f.index.functions)
            push!(units, CorpusUnit(f.file, u, unit_name(fu, f.index), fu.firstline))
            unit_index[(f.file, u)] = length(units)
        end
    end

    # Resolve references first, counting the distinct units that reach each definition,
    # so cross-cutting names can be dropped before the weighted edges are built. A
    # reference in top-level code couples no unit, so it is skipped here.
    resolved = Tuple{Int, Vector{Int}}[]
    breadth = Dict{Int, Set{Int}}()
    for (f, ref, candidates) in corpus_references(files, table)
        ref.unit == 0 && continue
        src = unit_index[(f.file, ref.unit)]
        push!(resolved, (src, candidates))
        for di in candidates
            push!(get!(() -> Set{Int}(), breadth, di), src)
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

    within_edges = within_binding_edges(files, unit_index, within_ubiquity)
    return CorpusGraph(units, unit_index, edges, within_edges, file_mass)
end

# The within-file binding edges across the corpus: each file's [`binding_groups`](@ref)
# star-linked to its first member, local unit indices mapped to graph nodes. A language
# with no scopes query carries none.
function within_binding_edges(files::Vector{ParsedFile}, unit_index::Dict{Tuple{String, Int}, Int}, ubiquity::Float64)
    within = Dict{Tuple{Int, Int}, Float64}()
    for f in files
        scopes_query_for(f.language) === nothing && continue
        for members in binding_groups(f.index, ubiquity)
            base = get(unit_index, (f.file, members[1]), 0)
            base == 0 && continue
            for m in members
                node = get(unit_index, (f.file, m), 0)
                (node == 0 || node == base) && continue
                within[(base, node)] = get(within, (base, node), 0.0) + 1.0
            end
        end
    end
    return within
end

# Undirected weighted adjacency over the units: a coupling is mutual, so a directed
# edge and its reverse fold into one neighbour weight. With `within = true` the
# within-file binding edges fold in too, the view `:scattered` and `:low_cohesion` read.
# Self-loops cannot arise: a cross-file edge always joins units in different files, and a
# within edge skips `base != node` at build time.
function adjacency(graph::CorpusGraph; within::Bool = false)
    n = length(graph.units)
    adj = [Dict{Int, Float64}() for _ in 1:n]
    fold_edges!(adj, graph.edges)
    within && fold_edges!(adj, graph.within_edges)
    return adj
end

# Fold directed weighted edges into an undirected neighbour-weight adjacency, each edge
# added to both endpoints.
function fold_edges!(adj::Vector{Dict{Int, Float64}}, edges::Dict{Tuple{Int, Int}, Float64})
    for ((a, b), w) in edges
        adj[a][b] = get(adj[a], b, 0.0) + w
        adj[b][a] = get(adj[b], a, 0.0) + w
    end
    return adj
end

# Connected components of `nodeids` over `adj`, as a node-id vector per component, found
# by flood fill. Only edges between two nodes both in `nodeids` are followed, so
# restricting a within-view adjacency to one file's nodes drops its cross-file edges and
# counts the file's independent concerns, the LCOM4 reading `:low_cohesion` reports. Every
# node seeds its own component, so a unit with no binding edge stands alone.
function components(adj::Vector{Dict{Int, Float64}}, nodeids::Vector{Int})
    inset = Set(nodeids)
    seen = Set{Int}()
    out = Vector{Int}[]
    for start in nodeids
        start in seen && continue
        group = Int[]
        stack = [start]
        push!(seen, start)
        while !isempty(stack)
            nd = pop!(stack)
            push!(group, nd)
            for j in keys(adj[nd])
                (j in inset && !(j in seen)) || continue
                push!(seen, j)
                push!(stack, j)
            end
        end
        push!(out, group)
    end
    return out
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
