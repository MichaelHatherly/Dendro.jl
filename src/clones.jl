# Near-miss (Type-3) duplicate detection. The exact path in `corpus.jl` clusters
# functions whose whole node-type sequence hashes the same. This finds functions
# that are close but not identical, the copy-paste-then-edit shape, by comparing
# the multiset of their subtree hashes. It stays inside the syntactic bargain: no
# symbol resolution, just node types and tree shape, always within one language.

# Structural hash of every named subtree under a function, as a sorted multiset.
# Each hash folds a node's type with its children's hashes in order, so identifier
# names and literal values drop out (Type-2 invariant) while shape is kept. Two
# near-identical functions share most of these hashes; Dice over the two multisets
# scores how near. Nested callables are not descended into, matching `traverse_unit`.
function subtree_hashes(unit::FunctionUnit, profile::LanguageProfile)
    acc = UInt64[]
    subtree_hash!(acc, unit.node, profile)
    sort!(acc)
    return acc
end

# Push the structural hash of `node` and each named descendant into `acc`,
# returning `node`'s own hash so a parent can fold it in.
function subtree_hash!(acc::Vector{UInt64}, node::TreeSitter.Node, profile::LanguageProfile)
    h = hash(TreeSitter.node_type(node))
    for c in TreeSitter.named_children(node)
        TreeSitter.node_type(c) in profile.function_types && continue
        h = hash(subtree_hash!(acc, c, profile), h)
    end
    push!(acc, h)
    return h
end

# Count of each named node type under a function, the DECKARD characteristic
# vector. Same named-node set as `subtree_hashes`, so the counts sum to its length.
function node_histogram(unit::FunctionUnit, profile::LanguageProfile)
    hist = Dict{String,Int}()
    traverse_unit(unit.node, profile) do node, enter
        if enter && TreeSitter.is_named(node)
            t = TreeSitter.node_type(node)
            hist[t] = get(hist, t, 0) + 1
        end
        nothing
    end
    return hist
end

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
    histogram::Dict{String,Int}
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
function clone_vector(unit::CloneUnit, vocab::Dict{String,Int})
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
function near_miss_edges!(edges, units::Vector{CloneUnit}, idxs::Vector{Int},
                          threshold::Real, radius_factor::Real)
    length(idxs) < 2 && return edges

    vocab = Dict{String,Int}()
    for i in idxs, t in keys(units[i].histogram)
        get!(vocab, t, length(vocab) + 1)
    end

    bands = Dict{Int,Vector{Int}}()
    for i in idxs
        push!(get!(() -> Int[], bands, floor(Int, log2(units[i].size))), i)
    end

    seen = Set{Tuple{Int,Int}}()
    for b in sort!(collect(keys(bands)))
        query = bands[b]
        search = vcat(query, get(bands, b + 1, Int[]))
        tree = NearestNeighbors.BallTree(stack(clone_vector(units[i], vocab) for i in search),
                                         NearestNeighbors.Cityblock())
        radius = radius_factor * 2.0^(b + 1)
        hits = NearestNeighbors.inrange(tree, stack(clone_vector(units[i], vocab) for i in query), radius)
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

# Cluster the corpus's functions into near-miss groups, keyed by language so
# shapes never cross grammars. Returns one `:near_duplicate` finding per cluster,
# its `value` the weakest pairwise Dice in the cluster as a percent, suppressed
# when any member carries a `dendro-ignore: near_duplicate` directive.
function cluster_near_duplicates(files; min_size::Integer = DEFAULT_MIN_SIZE,
                                 threshold::Real = DEFAULT_THRESHOLD,
                                 radius_factor::Real = DEFAULT_RADIUS_FACTOR)
    units = CloneUnit[]
    for f in files
        for unit in functions(f.tree, f.profile)
            digest, size = structural_digest(unit, f.profile)
            size < min_size && continue
            loc = Location(f.file, unit.firstline, unit_name(unit, f.profile, f.source))
            sup = is_suppressed(f.directives, unit.firstline, :near_duplicate)
            push!(units, CloneUnit(f.language, loc, sup, subtree_hashes(unit, f.profile),
                                   node_histogram(unit, f.profile), digest, size))
        end
    end

    bylang = Dict{Symbol,Vector{Int}}()
    for (i, u) in enumerate(units)
        push!(get!(() -> Int[], bylang, u.language), i)
    end
    edges = Tuple{Int,Int,Float64}[]
    for idxs in values(bylang)
        near_miss_edges!(edges, units, idxs, threshold, radius_factor)
    end

    parent = collect(1:length(units))
    for (a, b, _) in edges
        parent[uf_find(parent, a)] = uf_find(parent, b)
    end
    members = Dict{Int,Set{Int}}()
    weakest = Dict{Int,Float64}()
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
        push!(findings, Finding(:near_duplicate, locations, round(Int, 100 * weakest[r]),
                                :high, nothing, :flag, suppressed))
    end
    sort!(findings; by = f -> (-length(f.locations), first(f.locations).file, first(f.locations).line))
    return findings
end
