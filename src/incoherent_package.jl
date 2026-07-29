# A directory whose contents belong somewhere else. Placement reads the corpus graph's
# communities per unit and `:scattered` reads them per file; this reads them per
# directory, the level a repo's layout is declared at. When most of a directory's units
# sit in communities anchored in other directories, the declared structure and the actual
# coupling disagree, and the layout is the thing that is wrong.
#
# It reads the filtered corpus graph, the one `:misplaced` reads, deliberately: community
# detection needs the cross-cutting cut, or a shared helper every module reaches for
# collapses the corpus into one community and no directory is anchored anywhere.
#
# The finding proposes a rearrangement rather than an edit, a weaker claim than the rest
# of Part II makes, and it overlaps with what `:scattered` already reports file by file.
# So it ships off by default, opted into through a `.dendro.toml`, and never enters the
# gate floor.
#
# Name-based and lexical like the rest of placement. The directory is read from the path,
# never from a declared module: some languages have those and some do not, and one rule
# firing differently across a polyglot corpus for that reason describes the languages
# rather than the code.

# Absolute band on the percentage of a directory's units whose community is anchored in
# another directory. Above 50 more of the directory belongs elsewhere than at home, the
# point where its name has stopped describing its contents; above 75 nearly all of it
# does, and the layout is telling the reader something false.
#
# Measured over 1646 scored directories in 37 corpora across ten languages (this package
# and seventeen other Julia packages, six Python corpora including flask and fastmcp,
# ripgrep, serde, guava, four JavaScript corpora, typescript-sdk, rails, sinatra,
# laravel, curl, go-sdk): 90% of directories score zero, 2.2% reach 25, 0.5%
# reach 50, and one directory in the whole measurement passed 75, MixedModels.jl's
# `src/profile` at 81, whose units all belong with the fitting code they extend. So warn
# at 50 selects that half-percent tail, and high at 75 stays rare enough that a project
# can clear it, the shape the other relational bands take.
const INCOHERENT_PACKAGE_BAND = (50, 75)

# A directory holding fewer units than this is not scored: a percentage over one or two
# units can only read 0, 50 or 100, so the score would say more about the directory's
# size than about its coupling.
const MIN_INCOHERENT_UNITS = 3

# The corpus needs this many scored directories before the percentile means anything;
# under it only the absolute band fires, as cohesion and placement do on a thin corpus.
const MIN_INCOHERENT_DIRS = 5

# The unit ordering the representatives follow: file path, then line, so a representative
# is fixed by the corpus rather than by a Dict's iteration order.
unit_order(u::CorpusUnit) = (u.file, u.line)

# The unit representing each community inside the directory it is anchored in, the target
# a finding points at. Earliest by `unit_order` among the community's units that live in
# its plurality directory. Every community has one: the plurality directory is the
# directory holding most of the community's units, so it holds at least one.
function community_anchor(graph::CorpusGraph, comm::Vector{Int}, plur::Dict{Int, String})
    anchors = Dict{Int, Int}()
    for (i, u) in enumerate(graph.units)
        c = comm[i]
        plur[c] == dirname(u.file) || continue
        cur = get(anchors, c, 0)
        (cur == 0 || unit_order(u) < unit_order(graph.units[cur])) && (anchors[c] = i)
    end
    return anchors
end

# The locations for one directory: per elsewhere-anchored community, the earliest unit of
# the directory in it, then the unit anchoring that community in the directory it belongs
# to. The pairs run in the order of their source units, so the finding reads as a list of
# moves.
function incoherent_locations(
        graph::CorpusGraph, comm::Vector{Int}, reps::Dict{Int, Int}, anchors::Dict{Int, Int}
    )
    sources = sort!(collect(values(reps)); by = nd -> unit_order(graph.units[nd]))
    locations = Location[]
    for nd in sources
        u = graph.units[nd]
        push!(locations, Location(u.file, u.line, u.name))
        t = graph.units[anchors[comm[nd]]]
        push!(locations, Location(t.file, t.line, t.name))
    end
    return locations
end

"""
    cluster_incoherent_packages(files, graph; band=$INCOHERENT_PACKAGE_BAND, cut=0.95, min_dirs=$MIN_INCOHERENT_DIRS) -> Vector{Finding}

Directories whose units mostly belong to communities anchored in other directories,
reported as `:incoherent_package`. The corpus graph's communities are the neighbourhoods
the references draw; each is anchored in the directory holding most of its units, and the
score is the percentage of a directory's units whose community is anchored elsewhere. Each
finding carries the absolute `band` on that percentage and the corpus percentile, fired
when either trips. Its locations pair one representative unit per elsewhere-anchored
community with the unit anchoring that community, so the directories the contents belong
to are named by real files.

A directory holding fewer than `MIN_INCOHERENT_UNITS` units is not scored, and one whose
units all stay home is left out of the percentile population, as `cluster_scattered`
leaves a file that scatters nowhere.

The finding proposes a rearrangement rather than a bounded edit, and it restates per
directory what `:scattered` reports per file, so the pass is off by default: enable it
with `incoherent_package = true` under `[rules]` in a `.dendro.toml`.

Failure modes:

  - The score reads low, and that is the main thing to know when interpreting it. A unit
    with no cross-file reference is its own community, anchored in its own directory, and
    counts as at home. Such units were between 54% and 100% of the units in every corpus
    measured, so a directory whose coupled units all belong elsewhere still scores well
    under 100 once its uncoupled units are counted. Read a score of 30 as substantial.
  - A language whose linkage resolves no cross-file references contributes no edges, every
    unit is its own community, and the pass is silent on it. So are `:misplaced` and
    `:scattered`, which read the same graph.
  - A repo holding all its code in one directory yields nothing: with one group, every
    community is anchored at home.
  - The directory comes from the path, not from a declared module, so a language that
    declares modules independently of its layout is judged on the layout.
  - The locations grow as a directory gains an elsewhere-anchored community. `errors(;
    since)` keys a finding by its location set, so that growth moves the key and the
    ratchet re-reports the directory, the same behaviour `:back_edge` carries and for the
    same reason: more of the directory belonging elsewhere is worsening.
"""
function cluster_incoherent_packages(
        files::Vector{ParsedFile}, graph::CorpusGraph;
        band::Tuple{Int, Int} = INCOHERENT_PACKAGE_BAND, cut::Real = 0.95,
        min_dirs::Integer = MIN_INCOHERENT_DIRS
    )
    comm = communities(graph)
    plur = community_plurality(graph, comm, u -> dirname(u.file))
    anchors = community_anchor(graph, comm, plur)
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)

    members = Dict{String, Vector{Int}}()
    for (i, u) in enumerate(graph.units)
        push!(get!(() -> Int[], members, dirname(u.file)), i)
    end

    scored = Tuple{Int, Vector{Location}}[]
    for dir in sort!(collect(keys(members)))
        nodes = members[dir]
        length(nodes) < MIN_INCOHERENT_UNITS && continue
        away = 0
        reps = Dict{Int, Int}()
        for nd in nodes
            c = comm[nd]
            plur[c] == dir && continue
            away += 1
            cur = get(reps, c, 0)
            (cur == 0 || unit_order(graph.units[nd]) < unit_order(graph.units[cur])) && (reps[c] = nd)
        end
        away == 0 && continue
        push!(scored, (round(Int, 100 * away / length(nodes)), incoherent_locations(graph, comm, reps, anchors)))
    end
    return directory_findings(
        RELATIONAL.incoherent_package, scored, directives, band, cut, length(scored) >= min_dirs
    )
end
