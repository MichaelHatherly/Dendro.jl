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
the duplicate clusters, `:change` the file graph at a `base` git ref against the file
graph at the working tree. `granularity` is `:file` (units collapsed to their file) or
`:unit` (one node per function). Active findings overlay onto the diagram: misplaced and
scattered nodes are classed, the misplaced suggested home drawn as a dashed edge, dead
definitions and public roots classed.

`:change` answers a reviewer's first question on a large diff, whether an edit stayed in
one place or rewired the corpus. Only the edges whose weight moved are drawn, with the
state in the arrow: `==>` for an edge added or grown, labelled with the definition names
it gained, and `-.->` for one weakened or gone. It needs `base`, and it is file-level
only, since a unit has no identity that survives a rename across revisions. A change that
rewired nothing draws a header and no edges. Unlike the other diagrams it reads git, so
`paths` must sit inside a repository and `base` must name a commit.

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

`profiles` is the language registry the corpus resolves file extensions through. It
defaults to the languages Dendro ships; pass `Dendro.resolve_profiles(config)` to draw a
graph over a language a `.dendro.toml` registers, which `analyze` does from its own config.
"""
function mermaid(
        io::IO, paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        graph::Symbol = :coupling, granularity::Symbol = :file,
        focus::Symbol = :auto, context::Integer = 1, base = nothing,
        ignore = String[], language = nothing, rules = BUILTIN_RULES, cut::Real = 0.95,
        min_size::Integer = DEFAULT_MIN_SIZE, threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR,
        profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    graph in (:coupling, :reachability, :clones, :change) ||
        error("Dendro: graph must be :coupling, :reachability, :clones or :change, got :$graph")
    granularity in (:file, :unit) ||
        error("Dendro: granularity must be :file or :unit, got :$granularity")
    focus in (:auto, :all, :findings) ||
        error("Dendro: focus must be :auto, :all or :findings, got :$focus")
    context >= 0 || error("Dendro: context must be >= 0, got $context")
    graph === :change && base === nothing &&
        error("Dendro: graph :change needs a `base` git ref to compare against")
    resolved = focus === :auto ? (granularity === :unit ? :findings : :all) : focus
    roots::Vector{String} = paths isa AbstractString ? [paths] : paths
    parse_at(at) = parse_corpus(collect_corpus(at, ignore, language; profiles); language, rules, profiles)
    files = parse_at(roots)
    if graph === :coupling
        table = corpus_symbols(files)
        mermaid_coupling(io, files, build_corpus_graph(files, table), table, granularity, cut, resolved, context)
    elseif graph === :reachability
        mermaid_reachability(io, files, corpus_symbols(files), granularity, resolved, context)
    elseif graph === :change
        granularity === :unit ? mermaid_change_unit(io, files, roots, base, parse_at) :
            mermaid_change(io, files, roots, base, parse_at)
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

# --- Change ---------------------------------------------------------------------------

"""
    EdgeDelta

One file-to-file dependency's movement between two revisions of the corpus.

`base` and `head` are the edge's weight at each revision, either of them zero where the
edge did not exist. `names` holds the definitions the edge gained, so a thickened arrow
says what arrived on it and not only that the coupling grew. An edge that lost references
names nothing: the definitions behind the drop are gone from head, and naming them sends
a reader to code that is not there.
"""
struct EdgeDelta
    from::String
    to::String
    base::Int
    head::Int
    names::Vector{String}
end

# A file graph's edges keyed by repo-relative endpoint paths. Two revisions number their
# nodes independently, so a path is the only key that means the same thing in both.
function edges_by_path(graph::FileGraph, root::AbstractString)
    out = Dict{Tuple{String, String}, FileEdge}()
    rels = Dict{String, String}()
    for ((a, b), e) in graph.edges
        out[(relative_to(rels, graph.files[a], root), relative_to(rels, graph.files[b], root))] = e
    end
    return out
end

# The file graph over a parsed corpus, the structure the change view diffs.
file_corpus_graph(files::Vector{ParsedFile}) = build_file_graph(files, corpus_symbols(files), Corpus(files))

# The edges whose weight moved between the two revisions, ordered by endpoint. An edge
# standing at the same weight in both is dropped: drawing every edge is the coupling view,
# and the question here is what the change did.
function change_deltas(base::Dict{Tuple{String, String}, FileEdge}, head::Dict{Tuple{String, String}, FileEdge})
    out = EdgeDelta[]
    for key in sort!(collect(union(keys(base), keys(head))))
        b = get(base, key, nothing)
        h = get(head, key, nothing)
        bw = b === nothing ? 0 : b.weight
        hw = h === nothing ? 0 : h.weight
        bw == hw && continue
        gained = h === nothing ? String[] : sort!(setdiff(h.names, b === nothing ? String[] : b.names))
        push!(out, EdgeDelta(key[1], key[2], bw, hw, gained))
    end
    return out
end

# A weight for a label: whole numbers plain, split references to one decimal. A reference
# matching several visible definitions splits its weight, so a within-file edge can land on
# a fraction, and "+1.5" is honest where "+2" would not be.
# Concrete rather than `::Real`: the file pass counts references as integers and the unit
# pass as split fractions, so an abstract signature would leave every comparison and
# subtraction below here dispatching dynamically for the sake of two callers.
weight_label(x::Float64) = isinteger(x) ? string(Int(x)) : string(round(x; digits = 1))

# The arrow and label an edge's movement draws with, shared by both granularities. Mermaid
# styles a link by its ordinal index (`linkStyle N`), so drawing state in colour would make
# every emitter count its links; the arrow shape carries it instead and survives being read
# without colour.
function state_arrow(base::Float64, head::Float64, names::Vector{String})
    head == 0 && return ("-.->", "gone")
    head < base && return ("-.->", string("-", weight_label(base - head)))
    named = isempty(names) ? "" : string(": ", join(names, ", "))
    base == 0 && return ("==>", string("new", named))
    return ("==>", string("+", weight_label(head - base), isempty(names) ? "" : string(" ", join(names, ", "))))
end

delta_arrow(d::EdgeDelta) = state_arrow(Float64(d.base), Float64(d.head), d.names)

# The change view: the edges that moved, drawn between their endpoint files. An untouched
# corpus draws a header and nothing else, which is the honest picture of a change that
# rewired nothing.
function change_file(io::IO, deltas::Vector{EdgeDelta})
    mmd_header(io, Pair{String, String}[])
    fileset = Set{String}()
    for d in deltas
        push!(fileset, d.from)
        push!(fileset, d.to)
    end
    fids = file_ids(fileset)
    file_nodes(io, fids, Set(keys(fids)))
    for d in deltas
        arrow, label = delta_arrow(d)
        println(io, "  ", fids[d.from], " ", arrow, "|", mmd_label(label), "| ", fids[d.to])
    end
    return nothing
end

# The change view over `roots`: the file graph at `base` against the file graph at the
# working tree. `parse_at` is the caller's own parse of a corpus, so the base revision is
# read with the same language, rule, and ignore settings as head without this carrying a
# copy of each of them.
function mermaid_change(io::IO, files::Vector{ParsedFile}, roots::Vector{String}, base, parse_at::P) where {P}
    root = git_toplevel(roots)
    head = edges_by_path(file_corpus_graph(files), root)
    prior = with_base_corpus(roots, base, root) do troot, tpaths
        isempty(tpaths) && return Dict{Tuple{String, String}, FileEdge}()
        return edges_by_path(file_corpus_graph(parse_at(tpaths)), troot)
    end
    return change_file(io, change_deltas(prior, head))
end

# --- Change, inside one file ----------------------------------------------------------

# A unit's identity across two revisions: the file it sits in and its name, both
# repo-relative. Overloads merge into one node, since a reader of a file thinks in function
# names, and a method's position in the file moves for reasons the reader does not care
# about.
const UnitKey = Tuple{String, String}

"""
    UnitDelta

One within-file binding edge's movement between two revisions.

`from` and `to` are unit names inside `file`, and `base`/`head` the edge's weight at each
revision, either zero where the edge did not exist. This is the companion to
[`EdgeDelta`](@ref) at the granularity below it: the file graph goes quiet when an edit
stays inside one file, and these are the edges it cannot see.
"""
struct UnitDelta
    file::String
    from::String
    to::String
    base::Float64
    head::Float64
end

# Each corpus unit's key, and each key's set of exact subtree digests. The digests are what
# lets a rename read as a rename: a name that vanished and a name that appeared with the
# same body are one unit, not a deletion and an addition.
function unit_keys_and_digests(files::Vector{ParsedFile}, graph::CorpusGraph, root::AbstractString)
    keys = Dict{Int, UnitKey}()
    digests = Dict{UnitKey, Set{UInt64}}()
    rels = Dict{String, String}()
    for f in files
        rel = relative_to(rels, f.file, root)
        for (u, fu) in enumerate(f.index.units)
            node = get(graph.unit_index, (f.file, u), 0)
            node == 0 && continue
            key = (rel, unit_name(fu, f.index))
            keys[node] = key
            _, _, digest, _ = clone_features(fu, f.index)
            push!(get!(() -> Set{UInt64}(), digests, key), digest)
        end
    end
    return keys, digests
end

# The within-file binding edges keyed by unit rather than by node index, overloads summed
# into their shared name. An edge whose endpoints sit in different files is not a within
# edge and cannot appear here.
function within_by_key(graph::CorpusGraph, keys::Dict{Int, UnitKey})
    out = Dict{Tuple{UnitKey, UnitKey}, Float64}()
    for ((a, b), w) in graph.within_edges
        (haskey(keys, a) && haskey(keys, b)) || continue
        ka, kb = keys[a], keys[b]
        ka == kb && continue
        out[(ka, kb)] = get(out, (ka, kb), 0.0) + w
    end
    return out
end

# Base units matched to the head units they were renamed into. A name present on one side
# only, whose body digest is shared with exactly one name present on the other side only
# and in the same file, is that unit under a new name. The uniqueness test is what keeps
# this honest: two identical stubs renamed together offer no evidence about which became
# which, so neither is claimed and both report as a deletion and an addition.
function unit_renames(base::Dict{UnitKey, Set{UInt64}}, head::Dict{UnitKey, Set{UInt64}})
    gone = [k for k in keys(base) if !haskey(head, k)]
    born = [k for k in keys(head) if !haskey(base, k)]
    out = Dict{UnitKey, UnitKey}()
    for g in sort!(gone)
        hits = [b for b in born if b[1] == g[1] && !isdisjoint(base[g], head[b])]
        length(hits) == 1 || continue
        # The head name must be as unambiguous as the base one, or two units are claiming it.
        back = [x for x in gone if x[1] == g[1] && !isdisjoint(base[x], head[hits[1]])]
        length(back) == 1 && (out[g] = hits[1])
    end
    return out
end

# The base edge set with every renamed endpoint spelled as its head name, so a rename alone
# leaves the two sets equal and reports nothing.
function apply_renames(edges::Dict{Tuple{UnitKey, UnitKey}, Float64}, renames::Dict{UnitKey, UnitKey})
    isempty(renames) && return edges
    out = Dict{Tuple{UnitKey, UnitKey}, Float64}()
    for ((a, b), w) in edges
        key = (get(renames, a, a), get(renames, b, b))
        out[key] = get(out, key, 0.0) + w
    end
    return out
end

# The within-file edges whose weight moved, ordered by file then endpoint. Same rule as the
# file-level pass: an edge standing at the same weight in both revisions says nothing.
function unit_deltas(base::Dict{Tuple{UnitKey, UnitKey}, Float64}, head::Dict{Tuple{UnitKey, UnitKey}, Float64})
    out = UnitDelta[]
    for key in sort!(collect(union(keys(base), keys(head))))
        bw = get(base, key, 0.0)
        hw = get(head, key, 0.0)
        bw == hw && continue
        push!(out, UnitDelta(key[1][1], key[1][2], key[2][2], bw, hw))
    end
    return out
end

# A mermaid id per unit key, the file's basename and the unit name, numbered where two keys
# slug the same so an id is never reused across files.
function unit_ids(keys::Vector{UnitKey})
    ids = Dict{UnitKey, String}()
    used = Set{String}()
    for k in sort!(copy(keys))
        slug = replace(string(basename(k[1]), "_", k[2]), r"[^A-Za-z0-9]" => "_")
        id = slug
        n = 1
        while id in used
            n += 1
            id = string(slug, "_", n)
        end
        push!(used, id)
        ids[k] = id
    end
    return ids
end

# The within-file change view: one subgraph per file that moved, its units as nodes and the
# binding edges that changed between them. Files whose units never moved are absent rather
# than drawn empty, since a box with nothing in it still costs the reader a look. `was`
# names the unit a node was renamed from, so a rename reads as one node with a history and
# not as a stranger.
function change_unit(io::IO, deltas::Vector{UnitDelta}, was::Dict{UnitKey, String})
    mmd_header(io, Pair{String, String}[])
    keyset = UnitKey[]
    for d in deltas
        push!(keyset, (d.file, d.from))
        push!(keyset, (d.file, d.to))
    end
    sort!(unique!(keyset))
    ids = unit_ids(keyset)
    subs = Tuple{String, String, Vector{String}}[]
    # Heaviest mover first. A reviewer reads top to bottom and stops when the budget of
    # attention runs out, so the order decides what gets read, not just what gets drawn.
    moved = Dict{String, Int}()
    for d in deltas
        moved[d.file] = get(moved, d.file, 0) + 1
    end
    for file in sort!(unique!([k[1] for k in keyset]); by = f -> (-moved[f], f))
        lines = String[]
        for k in keyset
            k[1] == file || continue
            label = haskey(was, k) ? string(k[2], " (was ", was[k], ")") : k[2]
            push!(lines, mmd_node(ids[k], label))
        end
        push!(subs, (replace(file, r"[^A-Za-z0-9]" => "_"), mmd_label(file), lines))
    end
    emit_subgraphs(io, subs)
    for d in deltas
        arrow, label = state_arrow(d.base, d.head, String[])
        println(io, "  ", ids[(d.file, d.from)], " ", arrow, "|", mmd_label(label), "| ", ids[(d.file, d.to)])
    end
    return nothing
end

# The within-file change view over `roots`. Same two revisions as the file-level pass, read
# one granularity down: each file's own binding edges, matched across the revisions by unit
# name and then by body digest.
function mermaid_change_unit(io::IO, files::Vector{ParsedFile}, roots::Vector{String}, base, parse_at::P) where {P}
    root = git_toplevel(roots)
    hgraph = build_corpus_graph(files, corpus_symbols(files))
    hkeys, hdig = unit_keys_and_digests(files, hgraph, root)
    hedges = within_by_key(hgraph, hkeys)
    bedges, bdig = with_base_corpus(roots, base, root) do troot, tpaths
        isempty(tpaths) && return (Dict{Tuple{UnitKey, UnitKey}, Float64}(), Dict{UnitKey, Set{UInt64}}())
        bfiles = parse_at(tpaths)
        bgraph = build_corpus_graph(bfiles, corpus_symbols(bfiles))
        bkeys, dig = unit_keys_and_digests(bfiles, bgraph, troot)
        return (within_by_key(bgraph, bkeys), dig)
    end
    renames = unit_renames(bdig, hdig)
    was = Dict{UnitKey, String}(v => k[2] for (k, v) in renames)
    return change_unit(io, unit_deltas(apply_renames(bedges, renames), hedges), was)
end
