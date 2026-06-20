# This file's units belong to several different modules. The cross-file companion to
# within-file `:low_cohesion`: where cohesion counts the independent concerns inside a
# file, scattering counts how many other modules pull the file's units away. The corpus
# graph holds only cross-file edges, so its communities alone would split every layered
# file, a file's own units never linked to each other. Folding each file's within-file
# binding edges (the same edges `file_components` links on, read from `index.bindings`)
# into the graph first lets a cohesive file's units settle into one community, so only a
# file whose units are each drawn toward a different other file scatters. Scored like
# cohesion: an absolute band on the count of elsewhere-anchored communities and the
# corpus percentile, fired when either trips. Name-based and lexical throughout.

# Absolute band on the count of distinct communities a file's units occupy that are
# anchored in another file. Zero is a file whose units stay home; the band marks where
# enough of them are pulled toward different modules to read regardless of the corpus. No
# external standard sets it, so it sits above an idiomatic corpus's spread, our own
# included, like the cohesion and placement bands. The percentile carries the
# corpus-relative signal.
const SCATTERED_BAND = (4, 6)

# A file with fewer units than this is too small to read as scattered.
const MIN_SCATTERED_UNITS = 2

# The corpus needs this many scored files before the count percentile means anything;
# under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_SCATTERED_FILES = 5

# The unit graph with each file's within-file binding edges folded in. The corpus graph
# carries only cross-file edges, so its communities never see a file's own cohesion;
# adding an edge between two units one of which references a binding the other defines
# (the `binding_groups` `:low_cohesion` reads) lets a cohesive file cluster into one
# community. Each group is star-linked to its first member, the same connectivity
# `file_components` builds, mapped from local unit indices to graph nodes.
function combined_adjacency(files::AbstractVector{ParsedFile}, graph::CorpusGraph, ubiquity::Real)
    adj = adjacency(graph)
    for f in files
        scopes_query_for(f.language) === nothing && continue
        for members in binding_groups(f.index, ubiquity)
            base = get(graph.unit_index, (f.file, members[1]), 0)
            base == 0 && continue
            for m in members
                node = get(graph.unit_index, (f.file, m), 0)
                (node == 0 || node == base) && continue
                adj[base][node] = get(adj[base], node, 0.0) + 1.0
                adj[node][base] = get(adj[node], base, 0.0) + 1.0
            end
        end
    end
    return adj
end

"""
    cluster_scattered(files, graph; band=$SCATTERED_BAND, cut=0.95, min_files=$MIN_SCATTERED_FILES, ubiquity=$COHESION_UBIQUITY) -> Vector{Finding}

Files whose units are pulled into several other modules, reported as `:scattered`. With
each file's within-file binding edges folded into the corpus graph, the units land in
communities; the score is the count of distinct communities a file's units occupy whose
plurality anchor is another file. Each finding carries the absolute `band` on that count
and the corpus percentile, fired when either trips. The locations are one representative
unit per elsewhere-anchored community, earliest line first. A language with no scopes
query is skipped, its functions carrying no bindings to fold in.
"""
function cluster_scattered(
        files::AbstractVector{ParsedFile}, graph::CorpusGraph;
        band::Tuple{Int, Int} = SCATTERED_BAND, cut::Real = 0.95,
        min_files::Integer = MIN_SCATTERED_FILES, ubiquity::Real = COHESION_UBIQUITY
    )
    findings = Finding[]
    comm = communities(combined_adjacency(files, graph, ubiquity))
    plur = community_plurality(graph, comm)

    scored = Tuple{ParsedFile, Int, Vector{Int}}[]
    for f in files
        scopes_query_for(f.language) === nothing && continue
        units = functions(f.index)
        length(units) < MIN_SCATTERED_UNITS && continue
        # The earliest-line representative graph node per elsewhere-anchored community.
        reps = Dict{Int, Int}()
        for u in eachindex(units)
            node = get(graph.unit_index, (f.file, u), 0)
            node == 0 && continue
            c = comm[node]
            plur[c] == f.file && continue
            cur = get(reps, c, 0)
            (cur == 0 || graph.units[node].line < graph.units[cur].line) && (reps[c] = node)
        end
        isempty(reps) && continue
        nodes = sort!(collect(values(reps)); by = nd -> graph.units[nd].line)
        push!(scored, (f, length(nodes), nodes))
    end
    isempty(scored) && return findings

    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, score, nodes) in scored
        absolute = severity(score, band)
        pct = enough ? searchsortedlast(counts, score) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        locations = [Location(f.file, graph.units[nd].line, graph.units[nd].name) for nd in nodes]
        sup = is_suppressed(f.directives, locations[1].line, :scattered)
        push!(findings, Finding(:scattered, locations, score, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
