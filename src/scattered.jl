# This file's units belong to several different modules. The cross-file companion to
# within-file `:low_cohesion`: where cohesion counts the independent concerns inside a
# file, scattering counts how many other modules pull the file's units away. Communities
# over the corpus graph's cross-file edges alone would split every layered file, a file's
# own units never linked to each other. Reading the graph's within view (`adjacency(graph;
# within = true)`) folds each file's binding edges in, so a cohesive file's units settle
# into one community and only a file whose units are each drawn toward a different other
# file scatters. Scored like cohesion: an absolute band on the count of elsewhere-anchored
# communities and the corpus percentile, fired when either trips. Name-based and lexical
# throughout.

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

"""
    cluster_scattered(files, graph; band=$SCATTERED_BAND, cut=0.95, min_files=$MIN_SCATTERED_FILES) -> Vector{Finding}

Files whose units are pulled into several other modules, reported as `:scattered`. With
each file's within-file binding edges folded into the corpus graph, the units land in
communities; the score is the count of distinct communities a file's units occupy whose
plurality anchor is another file. Each finding carries the absolute `band` on that count
and the corpus percentile, fired when either trips. The locations are one representative
unit per elsewhere-anchored community, earliest line first. A language with no scopes
query is skipped, its functions carrying no bindings to fold in.
"""
function cluster_scattered(
        files::Vector{ParsedFile}, graph::CorpusGraph;
        band::Tuple{Int, Int} = SCATTERED_BAND, cut::Real = 0.95,
        min_files::Integer = MIN_SCATTERED_FILES
    )
    findings = Finding[]
    comm = communities(adjacency(graph; within = true))
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
        sup = is_suppressed(f.directives, locations[1].line, RELATIONAL.scattered)
        push!(findings, Finding(RELATIONAL.scattered, locations, score, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
