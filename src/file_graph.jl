# The corpus file graph, the file-level companion to the unit graph in `corpus_graph.jl`.
# Nodes are corpus files; a directed edge records that one file's code references
# definitions in another, weighted by how many references cross it and carrying the
# evidence a finding needs to name an edit: the definition names behind the edge and the
# import statements that admit it.
#
# It reads the same resolution as the unit graph, name-based and lexical, but keeps the
# references the unit graph drops. `build_corpus_graph` discards a reference to a
# cross-cutting definition, which is right for placement: without that cut a unit is
# judged to belong wherever a shared helper lives. An architecture question is the
# opposite. A file every other file reaches for is the observation, not the noise, so the
# file graph is built from unfiltered references and the two graphs stay separate rather
# than one growing a mode flag.

# The most definition names one edge carries as evidence. A hot edge can name hundreds,
# which is a report nobody reads, so the heaviest few stand for it and `FileEdge.name_count`
# keeps the true number: a truncated list must say it is truncated.
const EDGE_NAMES_MAX = 8

"""
    FileEdge

One directed file-to-file dependency and the evidence for it.

- `weight`: how many resolved references cross the edge. A count, not a flag, so a
  heavily-used dependency is told apart from a single stray reference.
- `names`: the distinct definition names referenced, sorted, at most `EDGE_NAMES_MAX` of
  them and the heaviest first past that cap. "File A depends on file B" is not something
  to edit; "file A references `parse_config` from file B" is.
- `name_count`: how many distinct names the edge really carries, so a capped `names` reads
  as the sample it is.
- `declared`: the import or include statements admitting the edge, sorted. Empty for a
  language whose linkage query declares no statement for the dependency, in which case a
  finding falls back to a reference site.
"""
struct FileEdge
    weight::Int
    names::Vector{String}
    name_count::Int
    declared::Vector{Location}
end

"""
    ModuleGraph

A [`FileGraph`](@ref) contracted by a grouping function, the level the rules that read
directories rather than files work at. `groups` holds the sorted group keys, `index` maps a
key to its node, `members` lists the file nodes each group holds, and `edges` sums the
weight of every file edge crossing from one group to another. A file edge inside one group
is dropped: a group depending on itself says nothing.
"""
struct ModuleGraph
    groups::Vector{String}
    index::Dict{String, Int}
    members::Vector{Vector{Int}}
    edges::Dict{Tuple{Int, Int}, Int}
end

"""
    FileGraph

The corpus as files depending on files. `files` holds every corpus file, sorted, including
one with no units and one with no edges: a file nothing references and that references
nothing is a real architectural observation, and dropping it would move the denominator of
every corpus-relative score. `index` maps a path to its node, `edges` maps a
`(source, target)` node pair to its [`FileEdge`](@ref), and `first_line` gives each file a
representative line so a file-level finding never has to invent one.

`modules` is the graph contracted by directory, the reading every rule that works at
directory level takes. It is a field rather than a call each reader makes because the
readers have to agree: the clone ranking measures a cluster's spread across these groups
and `:back_edge` reads the grain between them, and two rules disagreeing about what a
module is would be a bug no test would name. [`module_graph`](@ref) contracts by another
key for a caller that wants one.

`edges` is a `Dict`, so its iteration order is not the corpus order. Sort the keys before
reading it into anything a report shows.
"""
struct FileGraph
    files::Vector{String}
    index::Dict{String, Int}
    edges::Dict{Tuple{Int, Int}, FileEdge}
    first_line::Vector{Int}
    modules::ModuleGraph
end

"""
    build_file_graph(files, table, corpus; linkage=resolve_linkage(files, table)) -> FileGraph

The file dependency graph over `files`, resolved against `table`. Every cross-file
reference contributes to the edge from the file it sits in to the file it names, and a
reference matching `k` visible definitions splits `1/k` across them, exactly as
[`build_corpus_graph`](@ref) does: choosing one of the `k` would mean choosing by something
other than the name, which is the line Dendro holds. The split accumulates as a `Float64`
and rounds once, when the edge is finalised.

Unlike the unit graph this drops no cross-cutting definition. Ubiquity is the signal an
architecture rule reads, not the noise it filters, so the graph is built from unfiltered
references.

Self-edges are skipped: a file's coupling to itself is what `:low_cohesion` reads, and
here it would only swamp every node's degree. `corpus` is the corpus path set the
language's [`Linkage`](@ref) resolver maps an import target through, which is how an edge
learns the statement that admits it. Pass a prebuilt `linkage` from
[`resolve_linkage`](@ref) to share one resolution with another pass over the corpus.

A corpus of one file returns its node and stops. Every rule over this graph withholds itself
on a corpus too thin for its own reason, and those floors differ, so the shared build guards
only on what none of them could read past: an edge joins two files, so one file carries none.
That is what spares a single-file gate run the reference walk and the linkage query pass.
"""
function build_file_graph(
        files::Vector{ParsedFile}, table::SymbolTable, corpus::Corpus;
        linkage::ResolvedLinkage = resolve_linkage(files, table)
    )
    paths = sort!(String[f.file for f in files])
    index = Dict{String, Int}(p => i for (i, p) in enumerate(paths))
    first_line = fill(1, length(paths))
    for f in files
        units = f.index.units
        isempty(units) || (first_line[index[f.file]] = units[1].firstline)
    end
    if length(files) < 2
        empty_edges = Dict{Tuple{Int, Int}, FileEdge}()
        return FileGraph(paths, index, empty_edges, first_line, module_graph(paths, empty_edges, dirname))
    end

    # A reference in top-level code counts here where the unit graph skips it: the file
    # depends on the target whether or not a function encloses the reference.
    mass = Dict{Tuple{Int, Int}, Float64}()
    names = Dict{Tuple{Int, Int}, Dict{String, Float64}}()
    for reference in linkage.references
        src = index[reference.file.file]
        candidates = reference.candidates
        share = 1.0 / length(candidates)
        for di in candidates
            d = table.defs[di]
            dst = get(index, d.file, 0)
            (dst == 0 || dst == src) && continue
            key = (src, dst)
            mass[key] = get(mass, key, 0.0) + share
            byname = get!(() -> Dict{String, Float64}(), names, key)
            byname[d.name] = get(byname, d.name, 0.0) + share
        end
    end

    declared = declared_edges(files, corpus, Dict{String, Int}(to_posix(p) => i for (i, p) in enumerate(paths)))
    edges = Dict{Tuple{Int, Int}, FileEdge}()
    empty_locations = Location[]
    for key in sort!(collect(keys(mass)))
        byname = names[key]
        sites = sort!(copy(get(declared, key, empty_locations)); by = loc -> (loc.file, loc.line, loc.unit))
        edges[key] = FileEdge(edge_weight(mass[key]), top_names(byname), length(byname), sites)
    end
    return FileGraph(paths, index, edges, first_line, module_graph(paths, edges, dirname))
end

# The reference count of an edge whose split references sum to `mass`. An edge exists only
# because a reference built it, so the count floors at one: rounding a half-reference to
# zero would report a dependency the code has as no dependency at all.
edge_weight(mass::Float64) = max(1, round(Int, mass))

# The names standing for one edge: the heaviest `EDGE_NAMES_MAX`, returned sorted. Ties
# break on the name, so the selection follows the edge's own weights rather than the order
# a `Dict` happened to yield.
function top_names(byname::Dict{String, Float64})
    ranked = sort!(collect(keys(byname)); by = name -> (-byname[name], name))
    length(ranked) > EDGE_NAMES_MAX && resize!(ranked, EDGE_NAMES_MAX)
    return sort!(ranked)
end

# The declared import and include statements per file edge: each target a file names,
# resolved through its language's linkage to corpus paths, recorded at the statement's
# location on the edge it admits. `nodes` keys the corpus paths the resolvers build, which
# are POSIX-separated whatever the host uses. A statement resolving to no corpus file, a
# stdlib or a generated module, records nothing, and a statement admitting an edge no
# reference crosses attaches to nothing: an edge is a reference, never a declaration.
#
# The query walk and the target resolution are per file and read only, so they fan out; only
# the fold into the shared edge map is serial. Folding in corpus order keeps the location
# lists identical at any thread count, which the file graph's determinism item asserts.
function declared_edges(files::Vector{ParsedFile}, corpus::Corpus, nodes::Dict{String, Int})
    per_file = Vector{Vector{Tuple{Int, Int, Location}}}(undef, length(files))
    parallel_map!(i -> file_declared_edges(files[i], corpus, nodes), per_file)
    out = Dict{Tuple{Int, Int}, Vector{Location}}()
    for entries in per_file
        for (src, dst, loc) in entries
            push!(get!(() -> Location[], out, (src, dst)), loc)
        end
    end
    return out
end

# One file's share of the declared edges: each corpus path its statements resolve to
# (`resolved_targets`), read into the `(source node, target node, statement site)` the fold
# records. A path outside the corpus and a statement naming the file's own node record
# nothing.
function file_declared_edges(f::ParsedFile, corpus::Corpus, nodes::Dict{String, Int})
    out = Tuple{Int, Int, Location}[]
    src = nodes[to_posix(f.file)]
    for (path, line) in resolved_targets(f, corpus)
        dst = get(nodes, path, 0)
        (dst == 0 || dst == src) && continue
        push!(out, (src, dst, Location(f.file, line, "")))
    end
    return out
end

"""
    module_graph(paths, fedges, key) -> ModuleGraph

Contract a file graph's `paths` and `fedges` by `key`, which maps a file path to the group
it belongs to. `build_file_graph` runs it by `dirname` and keeps the result as
[`FileGraph`](@ref)'s `modules`, the contraction every directory-level rule reads.
Grouping by directory needs no query work, is available in every language, and is what a
repo usually means by a module. A declared-module grouping exists in some languages and not
others, which would make one rule fire differently across a polyglot corpus for reasons
unrelated to the code, so it is not what the graph carries.

Takes the pieces, not the graph, because the graph is what it helps build: a `FileGraph`
holds its own contraction, so there is nothing to contract from yet when this runs.

Edge weights sum across the file edges crossing between two groups; an edge inside one
group is dropped.
"""
function module_graph(paths::Vector{String}, fedges::Dict{Tuple{Int, Int}, FileEdge}, key::Function)
    labels = String[String(key(path)::AbstractString) for path in paths]
    groups = sort!(unique(labels))
    index = Dict{String, Int}(g => i for (i, g) in enumerate(groups))
    members = [Int[] for _ in groups]
    for (node, label) in enumerate(labels)
        push!(members[index[label]], node)
    end
    edges = Dict{Tuple{Int, Int}, Int}()
    for (src, dst) in sort!(collect(keys(fedges)))
        pair = (index[labels[src]], index[labels[dst]])
        pair[1] == pair[2] && continue
        edges[pair] = get(edges, pair, 0) + fedges[(src, dst)].weight
    end
    return ModuleGraph(groups, index, members, edges)
end

"""
    module_communities(mg) -> Vector{Int}

A community label per module in `mg`, from the same modularity optimisation
[`communities`](@ref) runs over the unit graph, here over the undirected reading of the
contracted edges that `fold_edges!` builds. Modules that couple heavily land in one
neighbourhood; a module nothing couples to stands alone.
"""
module_communities(mg::ModuleGraph) =
    communities(fold_edges!([Dict{Int, Float64}() for _ in mg.groups], mg.edges))
