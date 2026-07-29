# The inward layout question. `:misplaced` asks where a unit belongs, `:scattered` asks it
# per file, `:incoherent_package` asks it per directory, and all three ask whether code
# belongs somewhere else. A directory whose contents all belong exactly where they are can
# still hold several independent groups that never became subdirectories. The contents are
# right and the internal shape is missing, and that is the observation this makes.
#
# The substrate is the file graph induced on one directory's direct children: a child file
# is one node, a child directory is one node with everything under it contracted in. The
# contraction is what makes one rule cover both directions. A directory of files divides
# into folders, and a directory of subdirectories groups those subdirectories under new
# parents. Same score, same gates, same proposal; only the things being moved differ.
#
# A directory is not partitioned. Cohesive groups are extracted into subdirectories and
# everything else stays where it is, because files and folders coexist in every real
# layout. Asking what fraction of the directory a partition covers punishes the ordinary
# case, where two cohesive subsystems sit beside a pile of genuinely miscellaneous files
# and the right answer is two folders with the rest left loose.
#
# One level per scan. A finding proposes one level and stops: a two-level tree of nine
# folders is a rearrangement nobody executes, and once the move lands the next scan reads
# directories that exist rather than a partition that might. The descent terminates on its
# own, since each level's children are fewer.
#
# Syntactic and shallow like the rest of the graph layer. The directory comes from the
# path, never from a declared module, and a group is who references whom by name.

# Absolute band on the best proposed folder's internal ratio, as a percentage: of the
# references its members make inside the directory, how many stay inside the folder. 100
# means the folder references nothing else the directory holds.
#
# Not from the corpus. The bands are a standard rather than a measurement, and there is no
# external threshold for how modular a directory should be, so the anchor is constructed:
# directories whose factoring is known because it was generated, read through the same
# score. Three groups of eight files read 100 when nothing crosses between them, 75 at one
# cross-reference per file, 59 at two, 48 at three and 44 at four. So `warn` at 60 sits just
# above the two-per-file level, where the groups are too entangled to separate without
# trading one tangle for another, and `high` at 85 sits above the one-per-file level, so
# only a near-disjoint split reaches it. Both edges state a coupling claim rather than a
# percentile.
#
# `warn` is also the bar a group has to clear to be proposed as a folder, which is why a
# project retuning the band retunes what gets proposed with it. One number, one opinion.
const DIVISIBLE_PACKAGE_BAND = (60, 85)

# How many children a group needs before it reads as a folder rather than a family. Eight
# groups of three files is genuinely eight independent families, and it splits perfectly, so
# the ratio calls it a clean division and proposes a subdirectory per family. A directory
# holding a folder for every three files is not the layout anybody wanted, which is why the
# size floor decides this before the ratio is read.
const MIN_DIVISIBLE_GROUP = 5

# A directory small enough to read at a glance does not want subdirectories whatever its
# shape, so the question does not apply below this many children.
const MIN_DIVISIBLE_NODES = 12

# The share of children that must carry a resolved reference before the directory is scored
# at all. A child with no edges is either genuinely independent or a reference the resolver
# missed, and nothing in a syntactic, name-based reader tells the two apart. Rather than
# treat one as the other the rule declines. A directory of thirty-five children where only
# twenty-two carry a resolved edge proposes exactly those twenty-two at a perfect ratio, and
# the thirteen left behind are exactly the isolated ones, so the ratio measures the resolver
# rather than the code. This is a stated scope limit of the same kind as the
# type-and-dispatch line, not a tuned threshold.
const MIN_DIVISIBLE_LINKED = 0.75

# The share of the directory a proposal has to place. Extracting five children from
# fifty-four leaves forty-nine loose and helps nobody, and a perfect internal ratio is
# trivially reached by any small disconnected clique.
const MIN_DIVISIBLE_PLACED = 0.25

# A lone proposed folder may not cover more than this much of the directory. One group
# holding everything is a rename, not a split: the cohesive-module case scores a perfect
# ratio purely because there is nothing outside it to reference. Two or more folders need no
# such guard, since extracting several out of one directory is a real change whatever they
# cover.
const MAX_SOLE_FOLDER = 0.7

# The share of its siblings a child may be reached by before it is dropped from the reading,
# the per-directory analog of `CORPUS_UBIQUITY`. The file graph keeps every cross-cutting
# reference by design, since ubiquity is what an architecture rule reads, and inside one
# directory that choice bites: a reporting module every pass reaches for pulls all of them
# into one group, and that group is an artifact of the coupling rather than a subsystem.
#
# The corpus cannot settle this number. Deleting nodes raises separation mechanically, so
# any statistic the cut improves rewards whatever deletes most. The constructed directories
# settle it instead, and only 0.8 satisfies every known answer: three independent groups
# beside a shared utility read 100 here, 46 with no cut at all, while 0.5 inverts the
# ordering of the entangled cases against each other and 0.34 empties the graph.
const DIRECTORY_UBIQUITY = 0.8

# The corpus needs this many scored directories before the percentile means anything; under
# it only the absolute band fires, as cohesion and placement do on a thin corpus.
const MIN_DIVISIBLE_DIRS = 5

# Files naming the directory they sit in. Moving one into a subdirectory of that directory
# renames the module, so they are dropped from the reading rather than offered as members of
# a folder that cannot hold them.
const MODULE_ROOT_FILES = ("lib.rs", "mod.rs", "__init__.py", "index.ts", "index.js", "package-info.java")

"""
    FolderCandidate

One group of a directory's children cohesive enough to be counted as a candidate
subdirectory. `members` holds the child indices, sorted, and `ratio` is the group's
internal ratio: of the reference weight its members carry inside the directory, the share
that stays inside the group. A ratio of 1.0 means the group references nothing else the
directory holds.

The per-group ratio is the claim, rather than a whole-directory modularity, because a
reader can check it: these eight files send 86% of their references to each other.
"""
struct FolderCandidate
    members::Vector{Int}
    ratio::Float64
end

"""
    ChildGraph

One directory's direct children as graph nodes. `names` holds the child paths, sorted;
`files` lists the file-graph nodes each child contracts, so a child directory carries
everything under it; and `adj` is the undirected adjacency, summing every file-graph edge
whose endpoints land in two different children. An edge inside one child is dropped, since
a child's coupling to itself is a question asked one level down.
"""
struct ChildGraph
    names::Vector{String}
    files::Vector{Vector{Int}}
    adj::Vector{Dict{Int, Float64}}
end

"""
    DirectoryReading

One directory the question applies to: its `graph` of children and the `candidates` a
proposal can be built from, best ratio first. A directory the question does not apply to
reads `nothing` instead, so the gates answer before anything is scored.
"""
struct DirectoryReading
    graph::ChildGraph
    candidates::Vector{FolderCandidate}
end

# The child of `dir` that `file` belongs to, as a path: the file itself when it sits
# directly in `dir`, otherwise the ancestor directory that does. `nothing` when the file
# sits outside `dir` entirely.
#
# Walked with `dirname` rather than split on a separator, since a corpus path carries the
# host's separator and a rule that read only `/` would see every Windows directory as
# holding one child.
function child_of(file::AbstractString, dir::AbstractString)
    parent = dirname(file)
    parent == dir && return String(file)
    while !isempty(parent) && parent != dirname(parent)
        dirname(parent) == dir && return parent
        parent = dirname(parent)
    end
    return nothing
end

"""
    child_graph(fg, dir) -> ChildGraph

The file graph of `fg` induced on `dir`'s direct children, contracted so that a child
directory is one node holding every file beneath it. The undirected reading is what the
community detection takes, so the two directions of a file pair sum into one weight.
"""
function child_graph(fg::FileGraph, dir::AbstractString)
    owner = Dict{Int, String}()
    for (node, path) in enumerate(fg.files)
        child = child_of(path, dir)
        child === nothing || (owner[node] = child)
    end
    names = sort!(collect(Set(values(owner))))
    index = Dict{String, Int}(name => i for (i, name) in enumerate(names))
    files = [Int[] for _ in names]
    for node in sort!(collect(keys(owner)))
        push!(files[index[owner[node]]], node)
    end
    adj = [Dict{Int, Float64}() for _ in names]
    for ((src, dst), edge) in fg.edges
        (haskey(owner, src) && haskey(owner, dst)) || continue
        a, b = index[owner[src]], index[owner[dst]]
        a == b && continue
        adj[a][b] = get(adj[a], b, 0.0) + edge.weight
        adj[b][a] = get(adj[b], a, 0.0) + edge.weight
    end
    return ChildGraph(names, files, adj)
end

# The children a proposal can move, and the subgraph on them: everything but the ones most
# of the directory reaches for and the ones naming the directory itself. Returns the kept
# children in their original numbering alongside the renumbered adjacency, so a group reads
# back as child names. A directory left with fewer than two movable children has nothing to
# divide, and comes back empty so the reading abstains rather than scoring a pair.
function movable_children(cg::ChildGraph)
    limit = max(3, floor(Int, DIRECTORY_UBIQUITY * (length(cg.names) - 1)))
    keep = [
        i for i in eachindex(cg.names)
            if length(cg.adj[i]) <= limit && !(basename(cg.names[i]) in MODULE_ROOT_FILES)
    ]
    length(keep) < 2 && return (Int[], Vector{Dict{Int, Float64}}())
    position = Dict{Int, Int}(child => i for (i, child) in enumerate(keep))
    sub = [Dict{Int, Float64}() for _ in keep]
    for (i, child) in enumerate(keep), (neighbour, weight) in cg.adj[child]
        haskey(position, neighbour) && (sub[i][position[neighbour]] = weight)
    end
    return (keep, sub)
end

# The candidate folders of one partition, best ratio first. A group below the size floor is
# not a folder, and a group whose members carry no reference at all has no ratio to report.
function folder_candidates(adj::Vector{Dict{Int, Float64}}, labels::Vector{Int}, keep::Vector{Int})
    members = Dict{Int, Vector{Int}}()
    for (i, label) in enumerate(labels)
        push!(get!(() -> Int[], members, label), i)
    end
    out = FolderCandidate[]
    for label in sort!(collect(keys(members)))
        group = members[label]
        length(group) >= MIN_DIVISIBLE_GROUP || continue
        inside = 0.0
        crossing = 0.0
        set = Set(group)
        for i in group, (j, weight) in adj[i]
            j in set ? (inside += weight / 2) : (crossing += weight)
        end
        total = inside + crossing
        total > 0 || continue
        push!(out, FolderCandidate(sort!([keep[i] for i in group]), inside / total))
    end
    sort!(out; by = c -> (-c.ratio, c.members))
    return out
end

# One directory's reading, or `nothing` when the question does not apply to it. The gates
# decide whether there is a proposal to make at all, and the score answers how good the best
# one is, the same division `MIN_COHESION_UNITS` and `MIN_HUB_CORPUS_FILES` make for their
# own rules.
function read_divisible(fg::FileGraph, dir::AbstractString)::Union{DirectoryReading, Nothing}
    cg = child_graph(fg, dir)
    length(cg.names) >= MIN_DIVISIBLE_NODES || return nothing
    # Coverage is a property of the directory's children, read before any child is dropped:
    # a child removed for being ubiquitous is linked by definition, and counting it as
    # unlinked would make abstention likelier the more coupled the directory is.
    linked = count(!isempty, cg.adj)
    linked >= MIN_DIVISIBLE_LINKED * length(cg.names) || return nothing
    keep, sub = movable_children(cg)
    isempty(keep) && return nothing
    candidates = folder_candidates(sub, communities(sub), keep)
    isempty(candidates) && return nothing
    placed = sum(length(c.members) for c in candidates)
    placed >= MIN_DIVISIBLE_PLACED * length(cg.names) || return nothing
    only_one = length(candidates) == 1 && length(candidates[1].members) > MAX_SOLE_FOLDER * length(cg.names)
    only_one && return nothing
    return DirectoryReading(cg, candidates)
end

# Every directory the corpus declares, from each file's own directory up through its
# ancestors. An ancestor is worth asking about because a directory whose children are all
# subdirectories is exactly the sibling-grouping case, and it is only reachable from above.
function corpus_directories(fg::FileGraph)
    dirs = Set{String}()
    for path in fg.files
        d = dirname(path)
        while !isempty(d) && d != "/" && d != "." && !(d in dirs)
            push!(dirs, d)
            d = dirname(d)
        end
    end
    return sort!(collect(dirs))
end

# The location standing for a set of children: the earliest corpus file any of them holds,
# at its first unit, carrying no unit name and `label` for what the site stands for. A child
# directory is represented by a file inside it, since a finding points at code rather than
# at a path, and the label is what carries the directory or the folder the file stands for.
function child_location(fg::FileGraph, cg::ChildGraph, children::Vector{Int}, label::String)
    node = minimum(minimum(cg.files[c]) for c in children)
    return Location(fg.files[node], fg.first_line[node], "", label)
end

"""
    cluster_divisible_packages(files, fg; band=$DIVISIBLE_PACKAGE_BAND, cut=0.95, min_dirs=$MIN_DIVISIBLE_DIRS) -> Vector{Finding}

Directories holding groups of children that could become subdirectories, reported as
`:divisible_package`. The directory is read as its direct children over the file graph, a
child file as one node and a child directory as one node with everything under it
contracted in, and the communities of that induced subgraph are the candidate groups. The
score is the best candidate's internal ratio as a percentage: of the reference weight its
members carry inside the directory, the share that stays inside the group.

Groups are extracted, not partitioned. Whatever no folder claims stays at the top level and
is expected to, so a directory of two cohesive subsystems beside a pile of miscellaneous
files yields two folders and keeps the rest loose.

Each finding carries the absolute `band` on that percentage and the corpus percentile,
fired when either trips. The first location stands for the directory, labelled with how
many of its children the proposal places, so the leftover reads off the finding: it is part
of the proposal, not a shortfall. One location per proposed folder follows, best ratio
first, each the earliest file that folder holds and labelled with its size and internal
ratio. A folder is proposed when its ratio reaches the band's warn edge, so retuning the
band retunes what gets proposed with it. A directory firing on the percentile alone has no
group that clears the bar and carries the directory alone, a warning with no proposal
rather than a proposal that does not hold, as `cluster_hub` does for a hub with one
audience.

The question does not apply to a directory below `MIN_DIVISIBLE_NODES` children, to one
where fewer than `MIN_DIVISIBLE_LINKED` of the children carry a resolved reference, to one
whose candidate groups place less than `MIN_DIVISIBLE_PLACED` of it, or to one whose single
candidate covers more than `MAX_SOLE_FOLDER` of it. Those directories are left out of the
percentile population too, as `cluster_incoherent_packages` leaves out a directory whose
units all stay home.

The finding proposes a rearrangement rather than a bounded edit, so the pass is off by
default: enable it with `divisible_package = true` under `[rules]` in a `.dendro.toml`.

Failure modes:

  - Only one level is proposed per scan. A group that itself wants dividing says so on the
    next scan, once it is a directory rather than a proposal.
  - A child every sibling reaches for is dropped before the groups are read, so it appears
    in no proposed folder. It stays at the top level, like everything else the proposal does
    not extract.
  - A file naming its own directory (`lib.rs`, `mod.rs`, `__init__.py`) cannot move into a
    subdirectory of it, so it is dropped alongside the ubiquitous children.
  - A directory of files with no resolved references between them is never assessed rather
    than assessed as independent. That is what `MIN_DIVISIBLE_LINKED` states, and a language
    whose linkage resolves nothing goes silent here for the same reason `:back_edge` and
    `:hub` do.
  - A chain of directories each holding one child is a real layout defect this cannot see.
    It is not about coupling, so no reading of the graph finds it.
  - The locations grow as a directory gains a proposed folder. `errors(; since)` keys a
    finding by its location set, so that growth moves the key and the ratchet re-reports the
    directory, the same behaviour `:back_edge` and `:incoherent_package` carry.
"""
function cluster_divisible_packages(
        files::Vector{ParsedFile}, fg::FileGraph;
        band::Tuple{Int, Int} = DIVISIBLE_PACKAGE_BAND, cut::Real = 0.95,
        min_dirs::Integer = MIN_DIVISIBLE_DIRS
    )
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    scored = Tuple{Int, Vector{Location}}[]
    for dir in corpus_directories(fg)
        reading = read_divisible(fg, dir)
        reading === nothing && continue
        cg, candidates = reading.graph, reading.candidates
        score = round(Int, 100 * candidates[1].ratio)
        folders = [c for c in candidates if round(Int, 100 * c.ratio) >= band[1]]
        placed = sum(length(c.members) for c in folders; init = 0)
        locations = [
            child_location(
                fg, cg, collect(eachindex(cg.names)),
                "$dir, $placed of $(length(cg.names)) children placed",
            ),
        ]
        for folder in folders
            push!(
                locations,
                child_location(
                    fg, cg, folder.members,
                    "$(length(folder.members)) children, $(round(Int, 100 * folder.ratio))% internal",
                ),
            )
        end
        push!(scored, (score, locations))
    end
    return directory_findings(
        RELATIONAL.divisible_package, scored, directives, band, cut, length(scored) >= min_dirs
    )
end
