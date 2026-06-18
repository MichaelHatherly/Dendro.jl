# Duplicate detection over tree-sitter structure. Two functions duplicated across
# the corpus, or two identical blocks inside different functions, are one question
# asked at different scales: does this shape appear more than once. Exact clones go
# through `cluster_duplicates`, near-misses through `cluster_near_duplicates`. Both
# stay inside the syntactic bargain, no symbol resolution, just node types and tree
# shape, always within one language.

# Minimum size, in named nodes, for a subtree to count as a possible clone. Below
# this a fragment is too small to be a meaningful duplicate: a one-line getter or a
# lone call is a handful of nodes, a real function or block clears it.
const DEFAULT_MIN_SIZE = 10

# One named subtree: its structural hash, the node, and its named-node count. The
# hash folds a node's type with its children's hashes in order, so identifier names
# and literal values drop out (Type-2 invariant) while shape is kept.
struct Subtree
    hash::UInt64
    node::TreeSitter.Node
    size::Int
end

"""
    subtrees(unit, profile) -> Vector{Subtree}

Every named subtree of a function unit, bottom-up, stopping at nested callables so
each is its own unit. The last entry is the unit's own node, the whole-function
subtree.
"""
# Collect a unit's nodes into a fresh vector via `collector!`, which fills it walking
# from the unit's node and stopping at nested callables.
collect_unit(collector!::F, ::Type{T}, unit::FunctionUnit, index::QueryIndex) where {F, T} =
    (acc = T[]; collector!(acc, unit.node, index); acc)

subtrees(unit::FunctionUnit, index::QueryIndex) =
    collect_unit(collect_subtrees!, Subtree, unit, index)

# Push every named subtree of `node` into `acc`, returning `node`'s own so a parent
# can fold its hash and size in.
function collect_subtrees!(acc::Vector{Subtree}, node::TreeSitter.Node, index::QueryIndex)
    h = hash(TreeSitter.node_type(node))
    size = 1
    for c in TreeSitter.named_children(node)
        is_function(c, index) && continue
        child = collect_subtrees!(acc, c, index)
        h = hash(child.hash, h)
        size += child.size
    end
    s = Subtree(h, node, size)
    push!(acc, s)
    return s
end

# Count of each named node type in a subtree set, the DECKARD characteristic vector.
function histogram_of(st::Vector{Subtree})
    hist = Dict{String, Int}()
    for s in st
        t = TreeSitter.node_type(s.node)
        hist[t] = get(hist, t, 0) + 1
    end
    return hist
end

# Sorted multiset of a function's subtree hashes, the input to Dice.
subtree_hashes(unit::FunctionUnit, index::QueryIndex) =
    sort!([s.hash for s in subtrees(unit, index)])

node_histogram(unit::FunctionUnit, index::QueryIndex) =
    histogram_of(subtrees(unit, index))

"""
    dice(a, b) -> Float64

Dice similarity in `[0, 1]` over two sorted multisets of subtree hashes:
`2|a ∩ b| / (|a| + |b|)`, counting multiplicity. `1.0` means identical structure,
`0.0` no shared subtree. Empty inputs return `0.0`.
"""
function dice(a::Vector{UInt64}, b::Vector{UInt64})
    total = length(a) + length(b)
    total == 0 && return 0.0
    i = j = 1
    inter = 0
    while i <= length(a) && j <= length(b)
        if a[i] == b[j]
            inter += 1
            i += 1
            j += 1
        elseif a[i] < b[j]
            i += 1
        else
            j += 1
        end
    end
    return 2 * inter / total
end

# The size floor for a subtree to anchor a clone, or `nothing` if it is neither a
# function nor a block. Blocks must clear twice the function floor: a short block of
# boilerplate, a couple of counter updates, coincides across unrelated code, while a
# whole small function is already a meaningful unit. Expressions and lone statements
# never anchor, so a recurring call shape is not a finding.
function anchor_floor(node::TreeSitter.Node, index::QueryIndex, min_size::Integer)
    is_function(node, index) && return min_size
    node in index.body && return 2 * min_size
    return nothing
end

# One indexed anchor in exact-clone detection: a function- or block-shaped subtree
# large enough to count, with the structural hash it buckets on and the location it
# reports. A concrete record so JET sees concrete field accesses through `subsumed`.
struct AnchorEntry
    language::Symbol
    hash::UInt64
    node::TreeSitter.Node
    file::String
    line::Int
    unit::String
    suppressed::Bool
end

"""
    cluster_duplicates(files; min_size=$DEFAULT_MIN_SIZE) -> Vector{Finding}

Exact clones across the corpus, keyed by language so shapes never collide across
grammars. Indexes every function- or block-shaped subtree large enough to matter,
buckets by structural hash, and reports each bucket of two or more as one
`:duplicate`. Functions clear `min_size` named nodes, blocks twice that. A
maximality filter keeps only the largest clone, so a duplicated function is reported
once, not again for every block nested inside it. Suppressed when any member carries
a `dendro-ignore: duplicate` directive.
"""
function cluster_duplicates(files::AbstractVector{ParsedFile}; min_size::Integer = DEFAULT_MIN_SIZE)
    entries = AnchorEntry[]
    buckets = Dict{Tuple{Symbol, UInt64}, Vector{Int}}()
    # Locate an anchor by its file and node identity. A node's identity is its byte
    # span plus grammar symbol (the `NodeId` convention), not the span alone: two
    # distinct anchors can share a span, and `subsumed` must resolve a parent to the
    # right one.
    anchor_at = Dict{Tuple{String, Int, Int, UInt16}, Int}()
    for f in files
        for unit in functions(f.index)
            name = unit_name(unit, f.index)
            for s in subtrees(unit, f.index)
                floor = anchor_floor(s.node, f.index, min_size)
                (floor === nothing || s.size < floor) && continue
                line = Int(TreeSitter.start_point(s.node).row) + 1
                sup = is_suppressed(f.directives, line, :duplicate)
                push!(
                    entries, AnchorEntry(
                        f.language, s.hash, s.node,
                        f.file, line, name, sup,
                    )
                )
                idx = length(entries)
                push!(get!(() -> Int[], buckets, (f.language, s.hash)), idx)
                anchor_at[(f.file, nodeid(s.node)...)] = idx
            end
        end
    end

    findings = Finding[]
    for idxs in values(buckets)
        length(idxs) < 2 && continue
        maximal = filter(i -> !subsumed(i, entries, buckets, anchor_at), idxs)
        length(maximal) < 2 && continue
        locations = [Location(entries[i].file, entries[i].line, entries[i].unit) for i in maximal]
        suppressed = any(entries[i].suppressed for i in maximal)
        push!(findings, Finding(:duplicate, locations, length(locations), :high, nothing, :flag, suppressed))
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end

# An anchor is subsumed when its nearest enclosing anchor is a clone of at least the
# same multiplicity: the larger clone already covers it. Multiplicity never rises
# going up the tree, so the nearest anchor ancestor is the one to check.
function subsumed(
        i::Int, entries::Vector{AnchorEntry},
        buckets::Dict{Tuple{Symbol, UInt64}, Vector{Int}},
        anchor_at::Dict{Tuple{String, Int, Int, UInt16}, Int}
    )
    e = entries[i]
    k = length(buckets[(e.language, e.hash)])
    p = TreeSitter.parent(e.node)
    while !TreeSitter.is_null(p)
        j = get(anchor_at, (e.file, nodeid(p)...), 0)
        if j != 0
            a = entries[j]
            return length(buckets[(a.language, a.hash)]) >= k
        end
        p = TreeSitter.parent(p)
    end
    return false
end

# Default Dice cutoff for a near-miss. Stricter than the GumTree container-match
# default (~0.5) because a review gate must stay quiet on incidental overlap.
const DEFAULT_THRESHOLD = 0.85

# Scales the neighbour-search radius to a function's size band. The radius is a
# count of node-histogram differences (L1), which grows with function size, so a
# fixed radius would relate small and large functions. `radius_factor` times the
# band's upper size bound keeps the prefilter generous, Dice then confirms.
const DEFAULT_RADIUS_FACTOR = 0.5

# One function carried through near-miss detection: where it is, whether an author
# accepted it, its subtree-hash multiset (for Dice), its node-type histogram (the
# characteristic vector), its exact digest (to skip exact clones), and its size.
struct CloneUnit
    language::Symbol
    location::Location
    suppressed::Bool
    hashes::Vector{UInt64}
    histogram::Dict{String, Int}
    digest::UInt64
    size::Int
end

# Iterative union-find with path halving; no recursive closure, so nothing boxes.
function uf_find(parent::Vector{Int}, x::Int)
    while parent[x] != x
        parent[x] = parent[parent[x]]
        x = parent[x]
    end
    return x
end

# Dense L1 vector for one unit over a shared per-language vocabulary.
function clone_vector(unit::CloneUnit, vocab::Dict{String, Int})
    v = zeros(Float64, length(vocab))
    for (t, c) in unit.histogram
        v[vocab[t]] = c
    end
    return v
end

# Candidate pairs within one language, confirmed by Dice. A characteristic-vector
# radius query (DECKARD) proposes pairs cheaply; size banding keeps the radius
# meaningful, querying each band against itself and the next size up so a pair
# straddling a band boundary is still seen. Each surviving pair becomes an edge
# weighted by its Dice score. Exact clones (equal digest) are left to the exact
# path, never re-reported here.
function near_miss_edges!(
        edges::Vector{Tuple{Int, Int, Float64}}, units::Vector{CloneUnit}, idxs::Vector{Int},
        threshold::Real, radius_factor::Real
    )
    length(idxs) < 2 && return edges

    vocab = Dict{String, Int}()
    for i in idxs, t in keys(units[i].histogram)
        get!(vocab, t, length(vocab) + 1)
    end

    bands = Dict{Int, Vector{Int}}()
    for i in idxs
        push!(get!(() -> Int[], bands, floor(Int, log2(units[i].size))), i)
    end

    seen = Set{Tuple{Int, Int}}()
    for b in sort!(collect(keys(bands)))
        query = bands[b]
        search = vcat(query, get(bands, b + 1, Int[]))
        tree = NearestNeighbors.BallTree(
            stack([clone_vector(units[i], vocab) for i in search]),
            NearestNeighbors.Cityblock()
        )
        radius = radius_factor * 2.0^(b + 1)
        hits = NearestNeighbors.inrange(tree, stack([clone_vector(units[i], vocab) for i in query]), radius)
        for (qi, neighbours) in enumerate(hits)
            i = query[qi]
            for pos in neighbours
                j = search[pos]
                i == j && continue
                pair = minmax(i, j)
                pair in seen && continue
                push!(seen, pair)
                units[pair[1]].digest == units[pair[2]].digest && continue
                score = dice(units[pair[1]].hashes, units[pair[2]].hashes)
                score >= threshold && push!(edges, (pair[1], pair[2], score))
            end
        end
    end
    return edges
end

# Cluster the corpus's functions into near-miss groups, keyed by language so shapes
# never cross grammars. Returns one `:near_duplicate` finding per cluster, its
# `value` the weakest pairwise Dice in the cluster as a percent, suppressed when any
# member carries a `dendro-ignore: near_duplicate` directive.
function cluster_near_duplicates(
        files::AbstractVector{ParsedFile}; min_size::Integer = DEFAULT_MIN_SIZE,
        threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR
    )
    units = CloneUnit[]
    for f in files
        for unit in functions(f.index)
            st = subtrees(unit, f.index)
            root = st[end]
            root.size < min_size && continue
            loc = Location(f.file, unit.firstline, unit_name(unit, f.index))
            sup = is_suppressed(f.directives, unit.firstline, :near_duplicate)
            hashes = sort!([s.hash for s in st])
            push!(units, CloneUnit(f.language, loc, sup, hashes, histogram_of(st), root.hash, root.size))
        end
    end

    bylang = Dict{Symbol, Vector{Int}}()
    for (i, u) in enumerate(units)
        push!(get!(() -> Int[], bylang, u.language), i)
    end
    edges = Tuple{Int, Int, Float64}[]
    for idxs in values(bylang)
        near_miss_edges!(edges, units, idxs, threshold, radius_factor)
    end

    parent = collect(1:length(units))
    for (a, b, _) in edges
        parent[uf_find(parent, a)] = uf_find(parent, b)
    end
    members = Dict{Int, Set{Int}}()
    weakest = Dict{Int, Float64}()
    for (a, b, score) in edges
        r = uf_find(parent, a)
        group = get!(() -> Set{Int}(), members, r)
        push!(group, a, b)
        weakest[r] = haskey(weakest, r) ? min(weakest[r], score) : score
    end

    findings = Finding[]
    for (r, group) in members
        idxs = sort!(collect(group); by = i -> (units[i].location.file, units[i].location.line))
        locations = [units[i].location for i in idxs]
        suppressed = any(units[i].suppressed for i in idxs)
        push!(
            findings, Finding(
                :near_duplicate, locations, round(Int, 100 * weakest[r]),
                :high, nothing, :flag, suppressed
            )
        )
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end
