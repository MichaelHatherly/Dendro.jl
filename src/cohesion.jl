# Within-file cohesion. A file's functions form a graph: two are linked when they
# reference a common file-local binding, a helper, type, or constant defined in the
# same file, the within view of the corpus unit graph (`graph_edges.jl`). A file that
# breaks into several disconnected components holds that many independent concerns, the
# LCOM4 reading of low cohesion. The signal stays syntactic and within one file, linking
# on a resolved binding, never a symbol across files. Scored like naturalness: an
# absolute band on the component count and the corpus percentile, fired when either
# trips.

# Absolute band on the number of components in a file. One component is a cohesive
# file; the band marks where the count of independent concerns is worth a look. No
# external standard sets it, so it sits above an idiomatic corpus's spread, our own
# included, the level at which a file holds enough disconnected concerns to read
# regardless of the corpus. The percentile carries the corpus-relative signal.
const LOW_COHESION_BAND = (4, 6)

# A file with fewer units than this is too small to read as disorganised.
const MIN_COHESION_UNITS = 2

# The corpus needs this many scored files before its component-count percentile means
# anything; under it only the absolute band fires, as naturalness does on a thin corpus.
const MIN_COHESION_FILES = 5

# A representative graph node per component, earliest line first: per component the
# earliest-line node, ties broken by the smaller node id. Within a file node-id order is
# local-unit order, so this matches a unit-order scan that replaces the rep only on a
# strictly smaller line.
function component_reps(graph::CorpusGraph, comps::Vector{Vector{Int}})
    keyed = Tuple{Int, Int}[]
    for group in comps
        rep = group[1]
        for nd in group
            graph.units[nd].line < graph.units[rep].line && (rep = nd)
        end
        push!(keyed, (graph.units[rep].line, rep))
    end
    sort!(keyed)
    return Int[nd for (_, nd) in keyed]
end

"""
    cluster_low_cohesion(files, graph; band=$LOW_COHESION_BAND, cut=0.95, min_files=$MIN_COHESION_FILES) -> Vector{Finding}

Files whose functions split into several independent components, reported as
`:low_cohesion`. The components come from the within view of `graph`
([`components`](@ref) over `adjacency(graph; within = true)` restricted to the file's
nodes); cross-file edges never join one file's units, so the count is the file's
independent concerns. Each finding carries both scores: the absolute `band` on the
component count and the corpus percentile, fired when either trips. The locations are
one representative function per component. A file with fewer than `$MIN_COHESION_UNITS`
units is too small to read as disorganised, and a language with no scopes query is
skipped, its functions carrying no bindings to link.
"""
function cluster_low_cohesion(
        files::Vector{ParsedFile}, graph::CorpusGraph; band::Tuple{Int, Int} = LOW_COHESION_BAND,
        cut::Real = 0.95, min_files::Integer = MIN_COHESION_FILES
    )
    findings = Finding[]
    adj = adjacency(graph; within = true)
    scored = Tuple{ParsedFile, Int, Vector{Int}}[]
    for f in files
        scopes_query_for(f.language) === nothing && continue
        n = length(functions(f.index))
        n < MIN_COHESION_UNITS && continue
        nodes = Int[graph.unit_index[(f.file, u)] for u in 1:n]
        reps = component_reps(graph, components(adj, nodes))
        push!(scored, (f, length(reps), reps))
    end
    isempty(scored) && return findings
    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, count, reps) in scored
        absolute = severity(count, band)
        pct = enough ? searchsortedlast(counts, count) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        locations = [Location(f.file, graph.units[nd].line, graph.units[nd].name) for nd in reps]
        sup = is_suppressed(f.directives, graph.units[reps[1]].line, RELATIONAL.low_cohesion)
        push!(findings, Finding(RELATIONAL.low_cohesion, locations, count, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value), first(f.locations).file, first(f.locations).line))
    return findings
end
