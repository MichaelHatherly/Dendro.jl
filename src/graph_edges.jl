# What a within-file binding edge is. A file's functions link when they reference a
# common file-local binding, a helper, type, or constant defined in the same file, read
# from the lexical bindings `bindings.jl` resolves. These edges are the within-file view
# of the corpus unit graph: `:low_cohesion` counts the components they form, `:scattered`
# folds them into the cross-file graph so a cohesive file's units settle into one
# community. Syntactic and within one file, linking on a resolved binding, never a symbol
# across files.

# A binding referenced by more than this fraction of a file's units is cross-cutting,
# a file-local utility every concern reaches for, and links nothing: keeping its edges
# would fold genuine concerns into one. Binding resolution already drops the imported
# and global names a string graph trips on, so the default keeps every file-local
# binding (1.0 never drops) and dogfood tunes it down only if needed.
const COHESION_UBIQUITY = 1.0

# Byte ranges of a file's units, the containment table `containing_unit` scans.
unit_ranges(index::QueryIndex) =
    Tuple{Int, Int}[TreeSitter.byte_range(u.node) for u in functions(index)]

# The innermost function unit whose byte span contains `[from, to]`, or 0 when the
# position lies in no function (top-level code). Units are few per file, so a scan.
function containing_unit(ranges::Vector{Tuple{Int, Int}}, from::Int, to::Int)
    best = 0
    best_span = typemax(Int)
    for (i, r) in enumerate(ranges)
        (r[1] <= from && to <= r[2]) || continue
        span = r[2] - r[1]
        span < best_span || continue
        best = i
        best_span = span
    end
    return best
end

# The within-file links a file's bindings imply: each entry lists the local unit indices
# that share one definition, the units referencing it plus, when it lives in a unit, its
# owner. A binding referenced by more than `ubiquity` of the units links nothing, a
# cross-cutting utility rather than a shared concern. The connectivity `:low_cohesion`
# reads as components and `:scattered` folds into the corpus graph.
function binding_groups(index::QueryIndex, ubiquity::Float64)
    units = functions(index)
    n = length(units)
    ranges = unit_ranges(index)
    # Units referencing one definition, keyed by the definition's identity.
    groups = Dict{NodeId, Vector{Int}}()
    for (refid, defid) in index.bindings
        ui = containing_unit(ranges, refid[1], refid[2])
        ui == 0 && continue
        push!(get!(() -> Int[], groups, defid), ui)
    end
    out = Vector{Int}[]
    threshold = ubiquity * n
    for (defid, members) in groups
        length(unique(members)) > threshold && continue
        owner = containing_unit(ranges, defid[1], defid[2])
        push!(out, owner == 0 ? members : push!(copy(members), owner))
    end
    return out
end

"""
    fan_out(unit, index) -> Int

Number of distinct callables the function invokes, from the `@callee` capture: the
called identifier, or a member/qualified call's final name, so `x.push(1)` and
`y.push(2)` are one target. Repeats count once, a nested unit's calls belong to it,
and the unit's own name never counts, which excludes both recursion and Julia's
call-shaped signature. The per-unit efferent-coupling scalar beside the binding
edges cohesion reads; zero for a language with no `@callee` capture.
"""
function fan_out(unit::FunctionUnit, index::QueryIndex)
    isempty(index.callee.nodes) && return 0
    ranges = unit_ranges(index)
    span = TreeSitter.byte_range(unit.node)
    own = unit_name(unit, index)
    names = Set{String}()
    for n in index.callee.nodes
        nid = nodeid(n)
        ui = containing_unit(ranges, nid[1], nid[2])
        (ui != 0 && ranges[ui] == span) || continue
        name = String(strip(TreeSitter.slice(index.source, n)))
        (isempty(name) || name == own) && continue
        push!(names, name)
    end
    return length(names)
end
