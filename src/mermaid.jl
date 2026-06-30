# Mermaid diagram export. The graphs Dendro builds during analysis, the corpus coupling
# graph, the dead-code reachability graph, and the clone clusters, rendered as mermaid
# `flowchart` text. A graph renderer takes the corpus, not `Findings`: the findings flatten
# a graph to `Location` pairs, so a structural diagram must reach the graph itself. The
# rendering is name-based and lexical like the rest, never typed.

# A label for inside a `["..."]` node: a double quote becomes the mermaid HTML entity and a
# newline a space, so neither breaks the line.
mmd_label(s::AbstractString) = replace(s, "\"" => "#quot;", "\n" => " ", "\r" => " ")

# A node line `id["label"]`, the label escaped. The node shape every view builds.
mmd_node(id::AbstractString, label::AbstractString) = string(id, "[\"", mmd_label(label), "\"]")

# The diagram header: the `flowchart` declaration and one `classDef` per overlay style.
function mmd_header(io::IO, classes::Vector{Pair{String, String}})
    println(io, "flowchart LR")
    for (name, style) in classes
        println(io, "  classDef ", name, " ", style, ";")
    end
    return nothing
end

# The distinct files across a sequence of corpus units or definitions. A typed loop, not a
# generator: a captured generator would erase the element type and read each `.file` as a
# dynamic field access.
function item_files(items::Union{Vector{CorpusUnit}, Vector{CorpusDef}})
    files = Set{String}()
    for it in items
        push!(files, it.file)
    end
    return files
end

# A readable node id per file, the file-level views share. The id is the file's basename
# with every non-alphanumeric character replaced, since a mermaid id admits no `/`, `.`, or
# `:`, so `src/corpus.jl` reads as `corpus_jl` in the edge lines rather than an opaque
# counter. Two files with the same basename get a numeric suffix, assigned in sorted order
# so the ids are stable.
function file_ids(files::Set{String})
    ids = Dict{String, String}()
    used = Set{String}()
    for file in sort!(collect(files))
        base = replace(basename(file), r"[^A-Za-z0-9]" => "_")
        slug = base
        k = 1
        while slug in used
            k += 1
            slug = string(base, "_", k)
        end
        push!(used, slug)
        ids[file] = slug
    end
    return ids
end

# Emit each subgraph: its id, its title, and its node lines. The frame `coupling_file`
# builds, the node lines already formed.
function emit_subgraphs(io::IO, subs::Vector{Tuple{String, String, Vector{String}}})
    for (id, title, lines) in subs
        println(io, "  subgraph ", id, "[\"", title, "\"]")
        for line in lines
            println(io, "    ", line)
        end
        println(io, "  end")
    end
    return nothing
end

# Group node `(subgraph-id, subgraph-title, node-id, node-label)` rows into subgraphs,
# groups in first-seen order, and emit each. The grouped-node frame the unit-level coupling
# and reachability views share; each builds its rows in one flat typed loop, so no captured
# closure widens the element type and no nested loop repeats across the two.
function emit_node_groups(io::IO, rows::Vector{Tuple{String, String, String, String}})
    order = String[]
    titles = Dict{String, String}()
    lines = Dict{String, Vector{String}}()
    for (gid, title, nid, label) in rows
        if !haskey(lines, gid)
            push!(order, gid)
            titles[gid] = title
            lines[gid] = String[]
        end
        push!(lines[gid], mmd_node(nid, label))
    end
    for gid in order
        println(io, "  subgraph ", gid, "[\"", titles[gid], "\"]")
        for line in lines[gid]
            println(io, "    ", line)
        end
        println(io, "  end")
    end
    return nothing
end

# One node per kept file, sorted, the file-level reachability and clone views share.
function file_nodes(io::IO, fids::Dict{String, String}, keep::Set{String})
    for file in sort!(collect(keys(fids)))
        file in keep || continue
        println(io, "  ", fids[file], "[\"", mmd_label(basename(file)), "\"]")
    end
    return nothing
end

# Class each file in `files` that carries a node, sorted, the file-level overlay.
function class_files(io::IO, fids::Dict{String, String}, files::Set{String}, class::String)
    for file in sort!(collect(files))
        haskey(fids, file) && println(io, "  class ", fids[file], " ", class)
    end
    return nothing
end

const COUPLING_CLASSES = ["misplaced" => "fill:#ffe0e0,stroke:#d33", "scattered" => "fill:#ffe6f5,stroke:#a3a"]
const REACH_CLASSES = ["root" => "fill:#e0f5e0,stroke:#3a3", "dead" => "fill:#eee,stroke:#999,stroke-dasharray:3 3"]
const CLONE_CLASSES = ["exact" => "fill:#e0ecff,stroke:#36c", "near" => "fill:#fff3d6,stroke:#d90"]

# The overlay style for a node kept only as context around a finding, not flagged itself.
# Added to the header when focusing so the eye separates the finding from its surroundings.
const CONTEXT_CLASS = "context" => "fill:#f4f4f4,stroke:#bbb"

# The kept node set when focusing on findings: the flagged nodes grown by `hops` steps over
# the undirected adjacency `adj`. `hops` of 0 keeps only the flagged nodes. Generic over the
# node id type, since the file views key by path and the unit views by index.
function neighbourhood(flagged::Set{T}, adj::Dict{T, Vector{T}}, hops::Integer) where {T}
    keep = copy(flagged)
    frontier = collect(flagged)
    for _ in 1:hops
        nxt = T[]
        for n in frontier
            haskey(adj, n) || continue
            for m in adj[n]
                m in keep && continue
                push!(keep, m)
                push!(nxt, m)
            end
        end
        frontier = nxt
    end
    return keep
end

# The header class list for a view, the context style appended when focusing so a kept
# neighbour reads as background.
view_classes(base::Vector{Pair{String, String}}, focus::Symbol) =
    focus === :findings ? [base; CONTEXT_CLASS] : base

# The undirected adjacency of directed edge pairs, self-loops dropped, the seed structure
# `neighbourhood` walks. Generic over the node id, since the unit views key by index and
# the file views by path.
function undirected(pairs::AbstractVector{Tuple{V, V}}) where {V}
    adj = Dict{V, Vector{V}}()
    for (a, b) in pairs
        a == b && continue
        push!(get!(() -> V[], adj, a), b)
        push!(get!(() -> V[], adj, b), a)
    end
    return adj
end

# Class each kept file that carries no finding as context, so a focused file view greys its
# surroundings. A no-op when not focusing.
function file_context(io::IO, fids::Dict{String, String}, keep::Set{String}, flagged::Set{String}, focus::Symbol)
    focus === :findings || return nothing
    for file in sort!(collect(keep))
        (file in flagged || !haskey(fids, file)) && continue
        println(io, "  class ", fids[file], " context")
    end
    return nothing
end

"""
    mermaid(io, paths; graph=:coupling, granularity=:file, focus=:auto, context=1, ...)
    mermaid(paths; ...) -> nothing

Render one of Dendro's graphs over `paths` as a mermaid `flowchart`, written to `io`.
`graph` selects the diagram: `:coupling` the corpus reference graph behind `:misplaced`
and `:scattered`, `:reachability` the dead-code graph behind `:unreferenced`, `:clones`
the duplicate clusters. `granularity` is `:file` (units collapsed to their file) or `:unit`
(one node per function). Active findings overlay onto the diagram: misplaced and scattered
nodes are classed, the misplaced suggested home drawn as a dashed edge, dead definitions
and public roots classed.

`focus` trims the diagram to what the findings touch. `:findings` keeps only flagged nodes
and the `context` hops of graph neighbours around them, drawn greyed, so a unit-level graph
of a real corpus stays small enough to read and to render. `:all` keeps every node. `:auto`
(the default) resolves to `:findings` at `:unit` granularity, where the full graph is a
hairball, and `:all` at `:file`, where it is already legible. `context` is the neighbour
radius: `0` keeps only the flagged nodes, `1` their immediate neighbours. `:clones` is
already finding-only, so `focus` does not change it.

Unlike `github_annotations`, which renders `Findings`, this takes the corpus and rebuilds
the structure it draws, since a graph is not recoverable from findings. Redirect `io` to a
`.mmd` file to save the diagram, as the CI workflow does for annotations. The keyword
options match `analyze`'s clone and ignore tuning.
"""
function mermaid(
        io::IO, paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        graph::Symbol = :coupling, granularity::Symbol = :file,
        focus::Symbol = :auto, context::Integer = 1,
        ignore = String[], language = nothing, rules = BUILTIN_RULES, cut::Real = 0.95,
        min_size::Integer = DEFAULT_MIN_SIZE, threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR
    )
    graph in (:coupling, :reachability, :clones) ||
        error("Dendro: graph must be :coupling, :reachability or :clones, got :$graph")
    granularity in (:file, :unit) ||
        error("Dendro: granularity must be :file or :unit, got :$granularity")
    focus in (:auto, :all, :findings) ||
        error("Dendro: focus must be :auto, :all or :findings, got :$focus")
    context >= 0 || error("Dendro: context must be >= 0, got $context")
    resolved = focus === :auto ? (granularity === :unit ? :findings : :all) : focus
    roots::Vector{String} = paths isa AbstractString ? [paths] : paths
    files = parse_corpus(collect_corpus(roots, ignore, language); language, rules)
    if graph === :coupling
        table = corpus_symbols(files)
        mermaid_coupling(io, files, build_corpus_graph(files, table), table, granularity, cut, resolved, context)
    elseif graph === :reachability
        mermaid_reachability(io, files, corpus_symbols(files), granularity, resolved, context)
    else
        mermaid_clones(io, files, granularity, min_size, threshold, radius_factor)
    end
    return nothing
end

mermaid(paths; kw...) = mermaid(stdout, paths; kw...)

# --- Coupling -------------------------------------------------------------------------

# The corpus coupling graph as a flowchart: units (or files) as nodes, the cross-file
# reference edges weighted, the communities as subgraphs, and misplaced/scattered findings
# overlaid. The eight parameters are each a distinct rendering input the graph needs.
# dendro-ignore: parameter_count
function mermaid_coupling(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, granularity::Symbol, cut::Real, focus::Symbol, context::Integer)
    mmd_header(io, view_classes(COUPLING_CLASSES, focus))
    granularity === :unit ? coupling_unit(io, files, graph, table, cut, focus, context) :
        coupling_file(io, files, graph, cut, focus, context)
    return nothing
end

# The misplaced sources, each paired with its suggested-home node (`0` when the finding
# carries no home), and the units of scattered files. Computed once so the unit view can
# both seed the focus neighbourhood and draw the overlay from the same findings.
function coupling_flags(files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, cut::Real)
    node_at = Dict{Tuple{String, Int}, Int}()
    for (i, u) in enumerate(graph.units)
        node_at[(u.file, u.line)] = i
    end
    misplaced = Tuple{Int, Int}[]
    for f in cluster_misplaced(files, graph, table; cut)
        f.suppressed && continue
        src = first(f.locations)
        n = get(node_at, (src.file, src.line), 0)
        n == 0 && continue
        m = 0
        if length(f.locations) >= 2
            tgt = f.locations[2]
            m = get(node_at, (tgt.file, tgt.line), 0)
        end
        push!(misplaced, (n, m))
    end
    scattered = Set{Int}()
    sfiles = scattered_files(files, graph, cut)
    for (i, u) in enumerate(graph.units)
        u.file in sfiles && push!(scattered, i)
    end
    return misplaced, scattered
end

function coupling_unit(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, table::SymbolTable, cut::Real, focus::Symbol, context::Integer)
    comm = communities(graph)
    plur = community_plurality(graph, comm)
    misplaced, scattered = coupling_flags(files, graph, table, cut)
    keep = if focus === :findings
        seed = copy(scattered)
        for (n, m) in misplaced
            push!(seed, n)
            m == 0 || push!(seed, m)
        end
        neighbourhood(seed, undirected(collect(keys(graph.edges))), context)
    else
        Set(eachindex(graph.units))
    end
    rows = Tuple{String, String, String, String}[]
    for i in eachindex(comm)
        i in keep || continue
        c = comm[i]
        push!(rows, (string("community_", c), mmd_label(basename(get(plur, c, ""))), string("u", i), graph.units[i].name))
    end
    emit_node_groups(io, rows)
    for (a, b) in sort!(collect(keys(graph.edges)))
        (a in keep && b in keep) || continue
        println(io, "  u", a, " -->|", round(graph.edges[(a, b)]; digits = 1), "| u", b)
    end
    for (n, m) in misplaced
        n in keep && println(io, "  class u", n, " misplaced")
        (m != 0 && n in keep && m in keep) && println(io, "  u", n, " -.->|move| u", m)
    end
    for i in keep
        i in scattered && println(io, "  class u", i, " scattered")
    end
    coupling_context(io, keep, scattered, misplaced, focus)
    return nothing
end

# Class each kept unit that carries no finding as context, so a focused view greys its
# surroundings. A no-op when not focusing.
function coupling_context(io::IO, keep::Set{Int}, scattered::Set{Int}, misplaced::Vector{Tuple{Int, Int}}, focus::Symbol)
    focus === :findings || return nothing
    flagged = copy(scattered)
    for (n, _) in misplaced
        push!(flagged, n)
    end
    for i in sort!(collect(keep))
        i in flagged || println(io, "  class u", i, " context")
    end
    return nothing
end

function coupling_file(io::IO, files::Vector{ParsedFile}, graph::CorpusGraph, cut::Real, focus::Symbol, context::Integer)
    comm = communities(graph)
    plur = community_plurality(graph, comm)
    fids = file_ids(item_files(graph.units))
    agg = Dict{Tuple{String, String}, Float64}()
    for ((a, b), w) in graph.edges
        fa, fb = graph.units[a].file, graph.units[b].file
        fa == fb && continue
        agg[(fa, fb)] = get(agg, (fa, fb), 0.0) + w
    end
    sfiles = scattered_files(files, graph, cut)
    keep = focus === :findings ? neighbourhood(sfiles, undirected(collect(keys(agg))), context) : Set(keys(fids))
    by_comm = Dict{Int, Vector{String}}()
    for (file, c) in file_community(graph, comm)
        file in keep || continue
        push!(get!(() -> String[], by_comm, c), file)
    end
    subs = Tuple{String, String, Vector{String}}[]
    for c in sort!(collect(keys(by_comm)))
        lines = String[]
        for file in sort!(by_comm[c])
            push!(lines, mmd_node(fids[file], basename(file)))
        end
        push!(subs, (string("community_", c), mmd_label(basename(get(plur, c, ""))), lines))
    end
    emit_subgraphs(io, subs)
    for (a, b) in sort!(collect(keys(agg)))
        (a in keep && b in keep) || continue
        println(io, "  ", fids[a], " -->|", round(agg[(a, b)]; digits = 1), "| ", fids[b])
    end
    class_files(io, fids, sfiles, "scattered")
    file_context(io, fids, keep, sfiles, focus)
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
function mermaid_reachability(io::IO, files::Vector{ParsedFile}, table::SymbolTable, granularity::Symbol, focus::Symbol, context::Integer)
    mmd_header(io, view_classes(REACH_CLASSES, focus))
    adj, roots = reach_graph(files, table)
    seen = reachable(adj, roots)
    granularity === :unit ? reach_unit(io, table, adj, roots, seen, focus, context) :
        reach_file(io, table, adj, seen, focus, context)
    return nothing
end

# The directed reference edges as pairs, the seed `undirected` folds for a focus
# neighbourhood.
function reach_pairs(adj::Vector{Vector{Int}})
    pairs = Tuple{Int, Int}[]
    for i in eachindex(adj), j in adj[i]
        push!(pairs, (i, j))
    end
    return pairs
end

function reach_unit(io::IO, table::SymbolTable, adj::Vector{Vector{Int}}, roots::Set{Int}, seen::BitVector, focus::Symbol, context::Integer)
    dead = Set{Int}()
    for i in eachindex(table.defs)
        seen[i] || push!(dead, i)
    end
    keep = focus === :findings ? neighbourhood(dead, undirected(reach_pairs(adj)), context) : Set(eachindex(table.defs))
    fids = file_ids(item_files(table.defs))
    rows = Tuple{String, String, String, String}[]
    for (i, d) in enumerate(table.defs)
        i in keep || continue
        push!(rows, (fids[d.file], mmd_label(basename(d.file)), string("d", i), d.name))
    end
    emit_node_groups(io, rows)
    edges = Set{Tuple{Int, Int}}()
    for i in eachindex(adj), j in adj[i]
        (i == j || !(i in keep) || !(j in keep)) && continue
        push!(edges, (i, j))
    end
    for (i, j) in sort!(collect(edges))
        println(io, "  d", i, " --> d", j)
    end
    for i in sort!(collect(keep))
        if i in dead
            println(io, "  class d", i, " dead")
        elseif i in roots
            println(io, "  class d", i, " root")
        elseif focus === :findings
            println(io, "  class d", i, " context")
        end
    end
    return nothing
end

function reach_file(io::IO, table::SymbolTable, adj::Vector{Vector{Int}}, seen::BitVector, focus::Symbol, context::Integer)
    fids = file_ids(item_files(table.defs))
    edges = Set{Tuple{String, String}}()
    for i in eachindex(adj), j in adj[i]
        fa, fb = table.defs[i].file, table.defs[j].file
        fa == fb || push!(edges, (fa, fb))
    end
    alive = Set{String}()
    for i in eachindex(table.defs)
        seen[i] && push!(alive, table.defs[i].file)
    end
    dead = Set{String}()
    for file in keys(fids)
        file in alive || push!(dead, file)
    end
    keep = focus === :findings ? neighbourhood(dead, undirected(collect(edges)), context) : Set(keys(fids))
    file_nodes(io, fids, keep)
    for (a, b) in sort!(collect(edges))
        (a in keep && b in keep) || continue
        println(io, "  ", fids[a], " --> ", fids[b])
    end
    class_files(io, fids, dead, "dead")
    file_context(io, fids, keep, dead, focus)
    return nothing
end

# --- Clones ---------------------------------------------------------------------------

# The active clone clusters: exact and near-miss findings, each cluster's members the
# locations it covers.
function clone_findings(files::Vector{ParsedFile}, min_size::Integer, threshold::Real, radius_factor::Real)
    out = Finding[]
    append!(out, cluster_duplicates(files; min_size))
    append!(out, cluster_near_duplicates(files; min_size, threshold, radius_factor))
    active = Finding[]
    for f in out
        f.suppressed || push!(active, f)
    end
    return active
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
    file_nodes(io, fids, Set(keys(fids)))
    edges = Set{Tuple{String, String, Bool}}()
    for cl in clusters
        spans = String[]
        for loc in cl.locations
            push!(spans, loc.file)
        end
        sort!(unique!(spans))
        for k in 2:length(spans)
            push!(edges, (spans[1], spans[k], cl.metric === RELATIONAL.duplicate))
        end
    end
    for (a, b, exact) in sort!(collect(edges))
        println(io, "  ", fids[a], exact ? " --- " : " -.- ", fids[b])
    end
    return nothing
end
