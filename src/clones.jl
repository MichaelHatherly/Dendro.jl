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
    subtrees(unit, index) -> Vector{Subtree}

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

"""
    clone_features(unit, index) -> (sequence, histogram, digest, size)

A function's near-miss features from a single subtree walk: its pre-order subtree-hash
`sequence` (the Type-2 hashes in source order for the order-aware LCS), its node-type
`histogram` (the characteristic vector), its exact `digest`, and its `size`.
"""
function clone_features(unit::FunctionUnit, index::QueryIndex)
    st = subtrees(unit, index)
    root = st[end]
    return preorder_hashes(st), histogram_of(st), root.hash, root.size
end

# A subtree set's hashes in source order, the order-aware form the LCS compares. Read off a
# walk the caller already has, so a pass building other readings from the same subtrees
# pays for one walk.
preorder_hashes(st::Vector{Subtree}) = UInt64[s.hash for s in sort(st; by = s -> preorder_key(s.node))]

# Cap on the sequence length an LCS compares, bounding its O(n*m) cost. Beyond it the
# comparison reads only the first `LCS_CAP` nodes, so a clone among very large
# functions is judged on that prefix.
const LCS_CAP = 400

# Length of the longest common subsequence of two hash sequences, order-preserving,
# over a single rolling row. Reads at most `LCS_CAP` elements of each.
function lcs_length(a::Vector{UInt64}, b::Vector{UInt64})
    m = min(length(a), LCS_CAP)
    n = min(length(b), LCS_CAP)
    (m == 0 || n == 0) && return 0
    prev = zeros(Int, n + 1)
    curr = zeros(Int, n + 1)
    for i in 1:m
        for j in 1:n
            curr[j + 1] = a[i] == b[j] ? prev[j] + 1 : max(prev[j + 1], curr[j])
        end
        prev, curr = curr, prev
    end
    return prev[n + 1]
end

"""
    clone_similarity(a, b) -> Float64

NiCad's order-aware similarity of two subtree-hash sequences: `|LCS| / max(|a|, |b|)`
in `[0, 1]`, lengths capped at `LCS_CAP`. The `max` is asymmetric on purpose, so a
short fragment matching inside a long one scores low and a reordered match scores
below its multiset overlap. `1.0` means one sequence is a subsequence of the other,
`0.0` no shared order. Empty inputs return `0.0`.
"""
function clone_similarity(a::Vector{UInt64}, b::Vector{UInt64})
    denom = max(min(length(a), LCS_CAP), min(length(b), LCS_CAP))
    denom == 0 && return 0.0
    return lcs_length(a, b) / denom
end

# The size floor for a whole function to anchor a clone. A function with no control
# flow is boilerplate that coincides across unrelated code, a dispatch stub or a
# forwarding overload rather than a meaningful unit, so it clears the block floor
# instead of the function floor. Trivial and large still anchors: this only raises the
# bar, it never exempts.
unit_floor(node::TreeSitter.Node, index::QueryIndex, min_size::Integer) =
    has_control(node, index) ? min_size : 2 * min_size

# The size floor for a subtree to anchor a clone, or `nothing` if it is neither a
# function nor a block. Blocks must clear twice the function floor: a short block of
# boilerplate, a couple of counter updates, coincides across unrelated code, while a
# whole function with control flow is already a meaningful unit. Expressions and lone
# statements never anchor, so a recurring call shape is not a finding.
function anchor_floor(node::TreeSitter.Node, index::QueryIndex, min_size::Integer)
    is_function(node, index) && return unit_floor(node, index, min_size)
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
`:duplicate`. A function with control flow clears `min_size` named nodes; a
control-free function and a block clear twice that. A
maximality filter keeps only the largest clone, so a duplicated function is reported
once, not again for every block nested inside it. Suppressed when any member carries
a `dendro-ignore: duplicate` directive.
"""
function cluster_duplicates(files::Vector{ParsedFile}; min_size::Integer = DEFAULT_MIN_SIZE)
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
                sup = is_suppressed(f.directives, line, RELATIONAL.duplicate)
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
        push!(findings, Finding(RELATIONAL.duplicate, locations, length(locations), :high, nothing, :flag, suppressed))
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end

"""
    ModulePlacement

Where each corpus file sits in the module graph. `module_of` maps a file path to its
module node, `community` labels each module node with the neighbourhood modularity puts it
in. Together they are everything [`clone_distance`](@ref) needs, resolved once so a corpus
with three clone passes over it pays for one community optimisation.

Read off the graph's own `modules` contraction, the one `:back_edge` reads the grain
between, so a clone's distance and a back edge's grain are measured over the same groups.
"""
struct ModulePlacement
    module_of::Dict{String, Int}
    community::Vector{Int}
end

ModulePlacement(fg::FileGraph) = ModulePlacement(
    Dict{String, Int}(fg.files[i] => g for (g, files) in enumerate(fg.modules.members) for i in files),
    module_communities(fg.modules)
)

"""
    clone_distance(f, placement) -> Int

How far apart a clone cluster's members sit in the module graph: `0` within one file, `1`
within one directory, `2` within one community of directories, `3` spanning communities.

The scale reads how much of the system a duplicate implicates. Two copies inside one file
are local sloppiness, an edit one reader makes in one sitting. Two copies either side of a
community boundary are a missing abstraction: parts of the system that do not otherwise
couple each built the same thing, and the fix is a shared definition rather than a tidy-up.
The levels nest, since a file sits in one directory and a directory in one community, so
the widest gap between any two members is the level the whole cluster reads at.
"""
function clone_distance(f::Finding, placement::ModulePlacement)
    files = Set{String}(loc.file for loc in f.locations)
    length(files) == 1 && return 0
    mods = Set{Int}(placement.module_of[file] for file in files)
    length(mods) == 1 && return 1
    length(Set{Int}(placement.community[m] for m in mods)) == 1 && return 2
    return 3
end

"""
    rank_clones!(findings, placement) -> Vector{Finding}

Re-rank clone findings by [`clone_distance`](@ref), widest spread first. Each distance is
measured once and the findings permuted by a stable `sortperm` over the readings, so a
cluster's member set is walked once rather than once per comparison, and each pass's own
ordering, cluster size and then location for the structural passes, overlap score for
`:reimplementation`, survives inside one distance and keeps deciding ties.

Ranking only. `value`, `absolute`, and every finding's locations are untouched, so the
result is a permutation of the input. The gate depends on that: `:duplicate` is emitted at
the `:high` band and sits inside the floor [`errors`](@ref) returns, and the ratchet keys a
finding by `(metric, sorted location set)`, so a pure re-rank moves neither the floor nor a
key.
"""
function rank_clones!(findings::Vector{Finding}, placement::ModulePlacement)
    distances = Int[clone_distance(f, placement) for f in findings]
    return permute!(findings, sortperm(distances; rev = true, alg = Base.Sort.MergeSort))
end

"""
    nearest_anchor(lookup, node) -> Any

What `lookup` reports for the nearest ancestor of `node` it recognises, or `nothing` when
no ancestor does. The step every maximality filter shares: an anchor is redundant when the
anchor enclosing it most closely already covers it, so each walks up until an anchor
answers. `lookup` returns `nothing` for a node it does not index.
"""
function nearest_anchor(lookup::F, node::TreeSitter.Node) where {F}
    p = TreeSitter.parent(node)
    while !TreeSitter.is_null(p)
        answer = lookup(p)
        answer === nothing || return answer
        p = TreeSitter.parent(p)
    end
    return nothing
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
    j = nearest_anchor(e.node) do p
        hit = get(anchor_at, (e.file, nodeid(p)...), 0)
        hit == 0 ? nothing : hit
    end
    j === nothing && return false
    a = entries[j]
    return length(buckets[(a.language, a.hash)]) >= k
end

# Default similarity cutoff for a near-miss, the LCS fraction `|LCS| / max(|a|, |b|)`
# two functions must reach. A review gate must stay quiet on incidental overlap, so
# the bar is high.
const DEFAULT_THRESHOLD = 0.85

# Scales the neighbour-search radius to a function's size band. The radius is a
# count of node-histogram differences (L1), which grows with function size, so a
# fixed radius would relate small and large functions. `radius_factor` times the
# band's upper size bound keeps the prefilter generous, the LCS similarity then confirms.
const DEFAULT_RADIUS_FACTOR = 0.5

# One function carried through near-miss detection: where it is, whether an author
# accepted it, its pre-order node-type sequence (for the LCS verdict), its node-type
# histogram (the characteristic vector), its exact digest (to skip exact clones), and
# its size.
struct CloneUnit
    language::Symbol
    location::Location
    suppressed::Bool
    sequence::Vector{UInt64}
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

# Dense L1 vector for one node-type histogram over a shared vocabulary.
function clone_vector(histogram::Dict{String, Int}, vocab::Dict{String, Int})
    v = zeros(Float64, length(vocab))
    for (t, c) in histogram
        v[vocab[t]] = c
    end
    return v
end

# One side of a banded candidate query: each item's node-type histogram, the characteristic
# vector the radius query reads, and its size, which decides the band it lands in.
struct BandedSide
    histograms::Vector{Dict{String, Int}}
    sizes::Vector{Int}
end

# The search bands one query band reaches. Within one corpus, querying band `b` against `b`
# and `b+1` sees every pair straddling a boundary, since the lower member's own query covers
# the pair from the other side. A cross-corpus query is directional and has no such
# counterpart, so it reaches the band below as well.
const WITHIN_BANDS = (0, 1)
const CROSS_BANDS = (-1, 0, 1)

# The band lookup miss, shared so an absent neighbour band allocates nothing.
const NO_BAND = Int[]

# Group item indices into size bands by `floor(log2(size))`. An L1 distance over node
# histograms grows with function size, so a fixed radius would relate small and large
# functions; banding is what keeps the radius meaningful.
function size_bands(sizes::Vector{Int})
    bands = Dict{Int, Vector{Int}}()
    for (i, s) in enumerate(sizes)
        push!(get!(() -> Int[], bands, floor(Int, log2(s))), i)
    end
    return bands
end

"""
    banded_candidates(query, search, radius_factor, offsets) -> Vector{Tuple{Int, Int}}

The candidate pairs a banded characteristic-vector radius query (DECKARD) proposes, each
`(query index, search index)`. `offsets` says which search bands a query band reaches, and
`radius_factor` times the query band's upper size bound is the radius, so the prefilter
stays generous and an LCS similarity confirms.

Two sides rather than one index set, so the within-corpus near pass (which passes the same
side twice) and the cross-corpus one (which indexes the libraries and queries the project)
read the same banding rather than a second copy of it. The query is never a verdict.

Cheap relative to the LCS, so it stays serial, and its traversal order is deterministic,
bands sorted and hits in query order, which fixes the pair order a parallel confirmation
reads.
"""
function banded_candidates(
        query::BandedSide, search::BandedSide, radius_factor::Float64, offsets
    )
    vocab = Dict{String, Int}()
    for h in query.histograms, t in keys(h)
        get!(vocab, t, length(vocab) + 1)
    end
    for h in search.histograms, t in keys(h)
        get!(vocab, t, length(vocab) + 1)
    end

    qbands = size_bands(query.sizes)
    sbands = size_bands(search.sizes)
    out = Tuple{Int, Int}[]
    for b in sort!(collect(keys(qbands)))
        pool = Int[]
        for o in offsets
            append!(pool, get(sbands, b + o, NO_BAND))
        end
        isempty(pool) && continue
        asked = qbands[b]
        tree = NearestNeighbors.BallTree(
            stack([clone_vector(search.histograms[i], vocab) for i in pool]),
            NearestNeighbors.Cityblock()
        )
        radius = radius_factor * 2.0^(b + 1)
        hits = NearestNeighbors.inrange(
            tree, stack([clone_vector(query.histograms[i], vocab) for i in asked]), radius
        )
        for (qi, neighbours) in enumerate(hits)
            for pos in neighbours
                push!(out, (asked[qi], pool[pos]))
            end
        end
    end
    return out
end

# The near-miss similarity of two clone units, or zero when the size ratio alone rules
# a clone out, cheaper than the LCS. Concrete-typed, so the per-pair work stays static
# while the caller reaches it through a single dynamically-typed call.
function pair_similarity(units::Vector{CloneUnit}, i::Int, j::Int, threshold::Float64)
    a = units[i].sequence
    b = units[j].sequence
    la = min(length(a), LCS_CAP)
    lb = min(length(b), LCS_CAP)
    # Similarity is `|LCS| / max` and `|LCS|` is at most the shorter length, so a pair
    # whose size ratio is already under the threshold can never clear it.
    min(la, lb) < threshold * max(la, lb) && return 0.0
    return clone_similarity(a, b)
end

# The candidate pairs a banded radius query proposes within one language, deduped and with
# exact clones dropped. One corpus, so both sides of the query are the same units.
function candidate_pairs(units::Vector{CloneUnit}, idxs::Vector{Int}, radius_factor::Float64)
    side = BandedSide(
        Dict{String, Int}[units[i].histogram for i in idxs],
        Int[units[i].size for i in idxs],
    )
    pairs = Tuple{Int, Int}[]
    seen = Set{Tuple{Int, Int}}()
    for (a, b) in banded_candidates(side, side, radius_factor, WITHIN_BANDS)
        i, j = idxs[a], idxs[b]
        i == j && continue
        pair = minmax(i, j)
        pair in seen && continue
        push!(seen, pair)
        units[pair[1]].digest == units[pair[2]].digest && continue
        push!(pairs, pair)
    end
    return pairs
end

# Candidate pairs within one language, confirmed by LCS similarity, appended as weighted
# edges. `candidate_pairs` proposes cheaply; the LCS verdict is the dominant cost, so it
# runs in parallel over the proposed pairs (a size-ratio prefilter inside `pair_similarity`
# drops mismatched lengths before the O(n*m) work). Scores are written to a preallocated
# vector and read back in pair order, so the edge set is identical to the serial path.
# Exact clones (equal digest) are already dropped by `candidate_pairs`, never re-reported.
function near_miss_edges!(
        edges::Vector{Tuple{Int, Int, Float64}}, units::Vector{CloneUnit}, idxs::Vector{Int},
        threshold::Float64, radius_factor::Float64
    )
    length(idxs) < 2 && return edges
    pairs = candidate_pairs(units, idxs, radius_factor)
    scores = Vector{Float64}(undef, length(pairs))
    parallel_map!(scores) do k
        pair_similarity(units, pairs[k][1], pairs[k][2], threshold)
    end
    for k in eachindex(pairs)
        scores[k] >= threshold && push!(edges, (pairs[k][1], pairs[k][2], scores[k]))
    end
    return edges
end

"""
    clone_units(files, min_size, metric) -> Vector{CloneUnit}

Every function in `files` large enough to compare, with its near-miss features and the
directive that may accept a `metric` finding on it. Both near-miss passes read their units
this way, the within-corpus one and the cross-corpus one, differing only in the metric a
`dendro-ignore` names.
"""
function clone_units(files::Vector{ParsedFile}, min_size::Integer, metric::Symbol)
    units = CloneUnit[]
    for f in files
        for unit in functions(f.index)
            sequence, histogram, digest, size = clone_features(unit, f.index)
            size < unit_floor(unit.node, f.index, min_size) && continue
            loc = Location(f.file, unit.firstline, unit_name(unit, f.index))
            sup = is_suppressed(f.directives, unit.firstline, metric)
            push!(units, CloneUnit(f.language, loc, sup, sequence, histogram, digest, size))
        end
    end
    return units
end

"""
    by_language(items) -> Dict{Symbol, Vector{Int}}

Indices into `items` grouped by each one's `language`, so a shape is never compared across
grammars. Every pass that proposes pairs starts here, whatever record it carries.
"""
function by_language(items)
    bylang = Dict{Symbol, Vector{Int}}()
    for (i, x) in enumerate(items)
        push!(get!(() -> Int[], bylang, x.language), i)
    end
    return bylang
end

# Cluster the corpus's functions into near-miss groups, keyed by language so shapes
# never cross grammars. Returns one `:near_duplicate` finding per cluster, its
# `value` the weakest pairwise similarity in the cluster as a percent, suppressed when
# any member carries a `dendro-ignore: near_duplicate` directive.
function cluster_near_duplicates(
        files::Vector{ParsedFile}; min_size::Integer = DEFAULT_MIN_SIZE,
        threshold::Real = DEFAULT_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR
    )
    units = clone_units(files, min_size, RELATIONAL.near_duplicate)
    bylang = by_language(units)
    edges = Tuple{Int, Int, Float64}[]
    thr = Float64(threshold)
    rf = Float64(radius_factor)
    for idxs in values(bylang)
        near_miss_edges!(edges, units, idxs, thr, rf)
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
                RELATIONAL.near_duplicate, locations, round(Int, 100 * weakest[r]),
                :high, nothing, :flag, suppressed
            )
        )
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end
