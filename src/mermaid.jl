# Mermaid diagram export. The graphs Dendro builds during analysis, the corpus coupling
# graph, the dead-code reachability graph, and the clone clusters, rendered as mermaid
# `flowchart` text. A graph renderer takes the corpus, not `Findings`: the findings flatten
# a graph to `Location` pairs, so a structural diagram must reach the graph itself. The
# rendering is name-based and lexical like the rest, never typed.

# A label for inside a `["..."]` node: a double quote becomes the mermaid HTML entity and a
# newline a space, so neither breaks the line.
mmd_label(s) = replace(string(s), "\"" => "#quot;", "\n" => " ", "\r" => " ")

# The diagram header: the `flowchart` declaration and one `classDef` per overlay style.
function mmd_header(io::IO, classes::Vector{Pair{String, String}})
    println(io, "flowchart LR")
    for (name, style) in classes
        println(io, "  classDef ", name, " ", style, ";")
    end
    return nothing
end

# A stable `f<k>` id per file in sorted order, the node naming the file-level views share.
function file_ids(files::Set{String})
    ids = Dict{String, String}()
    for (k, file) in enumerate(sort!(collect(files)))
        ids[file] = string("f", k)
    end
    return ids
end

# One subgraph per group, in `order`: the subgraph id and title from each key, one node line
# per member. The grouped-node shape the unit-level coupling and reachability views share.
function emit_subgraphs(io::IO, order::Vector, members::Dict, id_of, title_of, node_of)
    for key in order
        println(io, "  subgraph ", id_of(key), "[\"", title_of(key), "\"]")
        for m in members[key]
            println(io, "    ", node_of(m))
        end
        println(io, "  end")
    end
    return nothing
end

# One node per file, sorted, the file-level reachability and clone views share.
function file_nodes(io::IO, fids::Dict{String, String})
    for file in sort!(collect(keys(fids)))
        println(io, "  ", fids[file], "[\"", mmd_label(basename(file)), "\"]")
    end
    return nothing
end

# Class each file in `files` that carries a node, sorted, the file-level overlay.
function class_files(io::IO, fids::Dict{String, String}, files, class::String)
    for file in sort!(collect(files))
        haskey(fids, file) && println(io, "  class ", fids[file], " ", class)
    end
    return nothing
end

const COUPLING_CLASSES = ["misplaced" => "fill:#ffe0e0,stroke:#d33", "scattered" => "fill:#ffe6f5,stroke:#a3a"]
const REACH_CLASSES = ["root" => "fill:#e0f5e0,stroke:#3a3", "dead" => "fill:#eee,stroke:#999,stroke-dasharray:3 3"]
const CLONE_CLASSES = ["exact" => "fill:#e0ecff,stroke:#36c", "near" => "fill:#fff3d6,stroke:#d90"]

"""
    mermaid(io, paths; graph=:coupling, granularity=:file, ...)
    mermaid(paths; ...) -> nothing

Render one of Dendro's graphs over `paths` as a mermaid `flowchart`, written to `io`.
`graph` selects the diagram: `:coupling` the corpus reference graph behind `:misplaced`
and `:scattered`, `:reachability` the dead-code graph behind `:unreferenced`, `:clones`
the duplicate clusters. `granularity` is `:file` (units collapsed to their file) or `:unit`
(one node per function). Active findings overlay onto the diagram: misplaced and scattered
nodes are classed, the misplaced suggested home drawn as a dashed edge, dead definitions
and public roots classed.

Unlike `github_annotations`, which renders `Findings`, this takes the corpus and rebuilds
the structure it draws, since a graph is not recoverable from findings. Redirect `io` to a
`.mmd` file to save the diagram, as the CI workflow does for annotations. The keyword
options match `analyze`'s clone and ignore tuning.
"""
function mermaid(
        io::IO, paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        graph::Symbol = :coupling, granularity::Symbol = :file,
        ignore = String[], language = nothing, rules = BUILTIN_RULES, cut::Real = 0.95,
        min_size::Integer = DEFAULT_MIN_SIZE, threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR
    )
    graph in (:coupling, :reachability, :clones) ||
        error("Dendro: graph must be :coupling, :reachability or :clones, got :$graph")
    granularity in (:file, :unit) ||
        error("Dendro: granularity must be :file or :unit, got :$granularity")
    roots::Vector{String} = paths isa AbstractString ? [paths] : paths
    files = parse_corpus(collect_corpus(roots, ignore, language); language, rules)
    if graph === :coupling
        table = corpus_symbols(files)
        mermaid_coupling(io, files, build_corpus_graph(files, table), table, granularity, cut)
    elseif graph === :reachability
        mermaid_reachability(io, files, corpus_symbols(files), granularity)
    else
        mermaid_clones(io, files, granularity, min_size, threshold, radius_factor)
    end
    return nothing
end

mermaid(paths; kw...) = mermaid(stdout, paths; kw...)

# --- Coupling -------------------------------------------------------------------------

# The corpus coupling graph as a flowchart: units (or files) as nodes, the cross-file
# reference edges weighted, the communities as subgraphs, and misplaced/scattered findings
# overlaid.
function mermaid_coupling(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, granularity::Symbol, cut::Real)
    mmd_header(io, COUPLING_CLASSES)
    granularity === :unit ? coupling_unit(io, files, graph, table, cut) : coupling_file(io, files, graph, cut)
    return nothing
end

function coupling_unit(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, cut::Real)
    comm = communities(graph)
    plur = community_plurality(graph, comm)
    groups = Dict{Int, Vector{Int}}()
    for i in eachindex(comm)
        push!(get!(() -> Int[], groups, comm[i]), i)
    end
    emit_subgraphs(
        io, sort!(collect(keys(groups))), groups,
        c -> string("community_", c),
        c -> mmd_label(basename(get(plur, c, ""))),
        i -> string("u", i, "[\"", mmd_label(graph.units[i].name), "\"]"),
    )
    for (a, b) in sort!(collect(keys(graph.edges)))
        println(io, "  u", a, " -->|", round(graph.edges[(a, b)]; digits = 1), "| u", b)
    end
    coupling_overlay(io, files, graph, table, cut)
    return nothing
end

# The misplaced and scattered overlay at unit granularity: each misplaced unit classed and
# linked to its suggested home, each unit of a scattered file classed.
function coupling_overlay(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, cut::Real)
    node_at = Dict{Tuple{String, Int}, Int}()
    for (i, u) in enumerate(graph.units)
        node_at[(u.file, u.line)] = i
    end
    for f in cluster_misplaced(files, graph, table; cut)
        f.suppressed && continue
        src = first(f.locations)
        n = get(node_at, (src.file, src.line), 0)
        n == 0 && continue
        println(io, "  class u", n, " misplaced")
        length(f.locations) >= 2 || continue
        tgt = f.locations[2]
        m = get(node_at, (tgt.file, tgt.line), 0)
        m == 0 && continue
        println(io, "  u", n, " -.->|move| u", m)
    end
    scattered = scattered_files(files, graph, cut)
    for (i, u) in enumerate(graph.units)
        u.file in scattered && println(io, "  class u", i, " scattered")
    end
    return nothing
end

function coupling_file(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, cut::Real)
    comm = communities(graph)
    plur = community_plurality(graph, comm)
    fids = file_ids(Set(u.file for u in graph.units))
    by_comm = Dict{Int, Vector{String}}()
    for (file, c) in file_community(graph, comm)
        push!(get!(() -> String[], by_comm, c), file)
    end
    emit_subgraphs(
        io, sort!(collect(keys(by_comm))), by_comm,
        c -> string("community_", c),
        c -> mmd_label(basename(get(plur, c, ""))),
        file -> string(fids[file], "[\"", mmd_label(basename(file)), "\"]"),
    )
    agg = Dict{Tuple{String, String}, Float64}()
    for ((a, b), w) in graph.edges
        fa, fb = graph.units[a].file, graph.units[b].file
        fa == fb && continue
        agg[(fa, fb)] = get(agg, (fa, fb), 0.0) + w
    end
    for (a, b) in sort!(collect(keys(agg)))
        println(io, "  ", fids[a], " -->|", round(agg[(a, b)]; digits = 1), "| ", fids[b])
    end
    class_files(io, fids, scattered_files(files, graph, cut), "scattered")
    return nothing
end

# The set of files an active `:scattered` finding covers.
function scattered_files(files::Vector{ParsedFile}, graph::CorpusGraph, cut::Real)
    out = Set{String}()
    for f in cluster_scattered(files, graph; cut)
        f.suppressed && continue
        for loc in f.locations
            push!(out, loc.file)
        end
    end
    return out
end

# The plurality community of each file's units: the module the file mostly sits in.
function file_community(graph::CorpusGraph, comm::Vector{Int})
    counts = Dict{String, Dict{Int, Int}}()
    for (i, u) in enumerate(graph.units)
        d = get!(() -> Dict{Int, Int}(), counts, u.file)
        d[comm[i]] = get(d, comm[i], 0) + 1
    end
    out = Dict{String, Int}()
    for (file, d) in counts
        c = dominant(d)
        c === nothing && continue
        out[file] = c
    end
    return out
end

# --- Reachability ---------------------------------------------------------------------

# The dead-code reachability graph as a flowchart: definitions (or files) as nodes, the
# reference edges directed, public roots and unreachable definitions classed.
function mermaid_reachability(io::IO, files::Vector{ParsedFile}, table::SymbolTable, granularity::Symbol)
    mmd_header(io, REACH_CLASSES)
    adj, roots = reach_graph(files, table)
    seen = reachable(adj, roots)
    granularity === :unit ? reach_unit(io, table, adj, roots, seen) : reach_file(io, table, adj, seen)
    return nothing
end

function reach_unit(io::IO, table::SymbolTable, adj::Vector{Vector{Int}}, roots::Set{Int}, seen::BitVector)
    by_file = Dict{String, Vector{Int}}()
    for (i, d) in enumerate(table.defs)
        push!(get!(() -> Int[], by_file, d.file), i)
    end
    fids = file_ids(Set(keys(by_file)))
    emit_subgraphs(
        io, sort!(collect(keys(by_file))), by_file,
        file -> fids[file],
        file -> mmd_label(basename(file)),
        i -> string("d", i, "[\"", mmd_label(table.defs[i].name), "\"]"),
    )
    edges = Set{Tuple{Int, Int}}()
    for i in eachindex(adj), j in adj[i]
        i == j || push!(edges, (i, j))
    end
    for (i, j) in sort!(collect(edges))
        println(io, "  d", i, " --> d", j)
    end
    for i in eachindex(table.defs)
        if !seen[i]
            println(io, "  class d", i, " dead")
        elseif i in roots
            println(io, "  class d", i, " root")
        end
    end
    return nothing
end

function reach_file(io::IO, table::SymbolTable, adj::Vector{Vector{Int}}, seen::BitVector)
    fids = file_ids(Set(d.file for d in table.defs))
    file_nodes(io, fids)
    edges = Set{Tuple{String, String}}()
    for i in eachindex(adj), j in adj[i]
        fa, fb = table.defs[i].file, table.defs[j].file
        fa == fb || push!(edges, (fa, fb))
    end
    for (a, b) in sort!(collect(edges))
        println(io, "  ", fids[a], " --> ", fids[b])
    end
    alive = Set(table.defs[i].file for i in eachindex(table.defs) if seen[i])
    dead = Set(file for file in keys(fids) if !(file in alive))
    class_files(io, fids, dead, "dead")
    return nothing
end

# --- Clones ---------------------------------------------------------------------------

# The active clone clusters: exact and near-miss findings, each cluster's members the
# locations it covers.
function clone_findings(files::Vector{ParsedFile}, min_size::Integer, threshold::Real, radius_factor::Real)
    out = Finding[]
    append!(out, cluster_duplicates(files; min_size))
    append!(out, cluster_near_duplicates(files; min_size, threshold, radius_factor))
    return filter(f -> !f.suppressed, out)
end

# The clone clusters as a flowchart: each cluster a subgraph of its members (or the files
# they span), exact clones solid and near-misses dashed.
function mermaid_clones(io::IO, files::Vector{ParsedFile}, granularity::Symbol, min_size::Integer, threshold::Real, radius_factor::Real)
    mmd_header(io, CLONE_CLASSES)
    clusters = clone_findings(files, min_size, threshold, radius_factor)
    granularity === :unit ? clones_unit(io, clusters) : clones_file(io, clusters)
    return nothing
end

function clones_unit(io::IO, clusters::Vector{Finding})
    counter = 0
    for (ci, cl) in enumerate(clusters)
        exact = cl.metric === RELATIONAL.duplicate
        kind = exact ? "duplicate" : "near-duplicate"
        println(io, "  subgraph clone_", ci, "[\"", kind, " ×", length(cl.locations), "\"]")
        ids = String[]
        for loc in cl.locations
            counter += 1
            id = string("c", counter)
            push!(ids, id)
            println(io, "    ", id, "[\"", mmd_label(string(loc.unit, " @ ", basename(loc.file), ":", loc.line)), "\"]")
        end
        println(io, "  end")
        for id in ids
            println(io, "  class ", id, exact ? " exact" : " near")
        end
        link = exact ? " --- " : " -.- "
        for k in 2:length(ids)
            println(io, "  ", ids[1], link, ids[k])
        end
    end
    return nothing
end

function clones_file(io::IO, clusters::Vector{Finding})
    fileset = Set{String}()
    for cl in clusters, loc in cl.locations
        push!(fileset, loc.file)
    end
    fids = file_ids(fileset)
    file_nodes(io, fids)
    edges = Set{Tuple{String, String, Bool}}()
    for cl in clusters
        spans = sort!(unique(loc.file for loc in cl.locations))
        for k in 2:length(spans)
            push!(edges, (spans[1], spans[k], cl.metric === RELATIONAL.duplicate))
        end
    end
    for (a, b, exact) in sort!(collect(edges))
        println(io, "  ", fids[a], exact ? " --- " : " -.- ", fids[b])
    end
    return nothing
end
