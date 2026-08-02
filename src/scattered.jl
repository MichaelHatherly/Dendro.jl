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
# enough of them are pulled toward different modules to read regardless of the corpus.
#
# Measured over 261 scored files across Dendro, DataFrames.jl, HTTP.jl, Makie, flask,
# requests, fastmcp, markitdown, ripgrep and Guava, the ten corpora `:hub` and
# `:split_audience` cite. Most of the spread is low: the pooled median is 2, the p90 is 6,
# and only Makie carries a file past 9. No external standard sets the level, so `warn` at 7
# sits above the p90 of every corpus measured but requests, firing on 6.5% of scored files
# in three of the ten. `high` at 10 enters the error floor every dogfooding package gates
# on, so it marks a file whose units have separated beyond argument: it fires on 4 of
# Makie's 145 files and on nothing else measured. The band this replaces, (4, 6), was
# asserted rather than measured, and put 11.5% of scored files in five of the ten corpora
# into that floor, which is a gate a layered corpus cannot satisfy and a level an ordinary
# one reaches without being wrong. Below the band the percentile carries the
# corpus-relative signal, which is what still reports the most scattered file in a corpus
# whose worst is a 6.
const SCATTERED_BAND = (7, 10)

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
    comm = communities(adjacency(graph; within = true))
    plur = community_plurality(graph, comm)

    scored = Tuple{ParsedFile, Int, Vector{Location}}[]
    for f in files
        scopes_query_for(f) === nothing && continue
        units = f.index.units
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
        # Each representative carries the file its community is anchored in. The count is the
        # score; this is the edit, and recovering it otherwise means rebuilding the graph.
        locations = Location[
            Location(
                    f.file, graph.units[nd].line, graph.units[nd].name,
                    string("belongs with ", label_path(plur[comm[nd]], f.file))
                ) for nd in nodes
        ]
        push!(scored, (f, length(locations), locations))
    end
    return scored_findings(RELATIONAL.scattered, scored, band, cut, min_files)
end
