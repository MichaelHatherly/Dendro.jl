# The two within-file edges a file's bindings imply, both read from the lexical bindings
# `bindings.jl` resolves and both syntactic and within one file, never a symbol across
# files.
#
# `binding_groups` is the undirected one: a file's units link when they reference a common
# file-local binding, a helper, type, or constant defined in the same file, and a nested
# callable links to the one enclosing it. It answers which units belong together, so it
# drops a cross-cutting binding every concern reaches for and says nothing about direction. `:low_cohesion` counts the components these form and
# `:scattered` folds them into the cross-file graph, so a cohesive file's units settle into
# one community.
#
# `binding_reference_edges` is the directed one: one edge per reference, from the unit that
# named it to the unit holding the definition. It answers which unit reached for which, so
# it keeps every binding and every unit rather than only the callables. The unit-level
# change diagram diffs these, where a partition's undirected relation has no arrow to draw.

# A binding referenced by more than this fraction of a file's units is cross-cutting,
# a file-local utility every concern reaches for, and links nothing: keeping its edges
# would fold genuine concerns into one. Binding resolution already drops the imported
# and global names a string graph trips on, so the default keeps every file-local
# binding (1.0 never drops) and dogfood tunes it down only if needed.
const COHESION_UBIQUITY = 1.0

# Byte ranges of a file's units, the containment table `containing_unit` scans.
unit_ranges(index::QueryIndex) =
    Tuple{Int, Int}[unit_span(u) for u in units(index)]

# The innermost function unit whose byte span contains `[from, to]`, or 0 when the
# position lies in no function (top-level code). Units are few per file, so a scan. A
# `skip` unit is passed over, so a unit's own span finds the unit enclosing it.
function containing_unit(ranges::Vector{Tuple{Int, Int}}, from::Int, to::Int, skip::Int = 0)
    best = 0
    best_span = typemax(Int)
    for (i, r) in enumerate(ranges)
        (i != skip && r[1] <= from && to <= r[2]) || continue
        span = r[2] - r[1]
        span < best_span || continue
        best = i
        best_span = span
    end
    return best
end

"""
    containing_callable(index, ranges, from, to, skip=0) -> Int

The innermost callable unit whose byte span contains `[from, to]`, or 0, passing over
the unit at index `skip`. The symbol table, the corpus graph and cohesion all ask which
definition owns a position, and top-level code is not one: a run of statements has no
name to resolve and cannot be moved the way a definition can, so a position inside one
belongs to no unit, exactly as it did before top-level code became a unit.

`ranges` is [`unit_ranges`](@ref) over the same index, so an index it returns is an
index into `units(index)`.
"""
function containing_callable(index::QueryIndex, ranges::Vector{Tuple{Int, Int}}, from::Int, to::Int, skip::Int = 0)
    ui = containing_unit(ranges, from, to, skip)
    ui == 0 && return 0
    return is_callable(units(index)[ui], index) ? ui : 0
end

# Each callable named from outside its own span, keyed by the name's identity. A binder
# such as `const f = () => ...` holds `f` beside the arrow, so no unit's span contains the
# definition of the unit it names, and a containment lookup would find no owner for it.
function bound_callables(index::QueryIndex)
    out = Dict{NodeId, Int}()
    for (ui, u) in enumerate(units(index))
        is_callable(u, index) || continue
        held = binder_name(unit_node(u), index)
        held === nothing || (out[nodeid(held)] = ui)
    end
    return out
end

# The within-file links a file's bindings imply: each entry lists the local unit indices
# that share one definition, the units referencing it plus, when it lives in or names a
# unit, its owner. A binding referenced by more than `ubiquity` of the units links nothing, a
# cross-cutting utility rather than a shared concern. A nested callable, a closure or a
# callback, also pairs with the callable enclosing it, whose concern it is part of. The
# connectivity `:low_cohesion` reads as components and `:scattered` folds into the corpus
# graph.
function binding_groups(index::QueryIndex, ubiquity::Float64)
    units = index.units
    n = length(units)
    ranges = unit_ranges(index)
    bound = bound_callables(index)
    # Units referencing one definition, keyed by the definition's identity.
    groups = Dict{NodeId, Vector{Int}}()
    for (refid, defid) in index.bindings
        ui = containing_callable(index, ranges, refid[1], refid[2])
        ui == 0 && continue
        push!(get!(() -> Int[], groups, defid), ui)
    end
    out = Vector{Int}[]
    threshold = ubiquity * n
    for (defid, members) in groups
        length(unique(members)) > threshold && continue
        owner = get(() -> containing_callable(index, ranges, defid[1], defid[2]), bound, defid)
        push!(out, owner == 0 ? members : push!(copy(members), owner))
    end
    for (ui, (from, to)) in enumerate(ranges)
        is_callable(units[ui], index) || continue
        parent = containing_callable(index, ranges, from, to, ui)
        parent == 0 || push!(out, [ui, parent])
    end
    return out
end

# The within-file links a file's bindings imply, read as references: each key is a
# `(referrer, definition)` pair of local unit indices and the weight how many times the
# referrer named it. A definition belongs to the unit it names or else the unit holding
# it. A reference outside any unit, a definition belonging to none, and a unit naming its
# own definition all draw nothing. The directed reading beside
# `binding_groups`' undirected one: an arrow here says which unit reached for which, which
# is what a diff of the within-file view reports. Every unit is a node, not only the
# callables, so a file-scope constant its functions read is the node they point at.
#
# No ubiquity cut. Dropping a name most of the file reaches for is right when the question
# is which concern a unit belongs to and wrong when it is what an edit rewired, the same
# split `file_graph.jl` draws over the cross-file references.
function binding_reference_edges(index::QueryIndex)
    ranges = unit_ranges(index)
    bound = bound_callables(index)
    out = Dict{Tuple{Int, Int}, Float64}()
    for (refid, defid) in index.bindings
        src = containing_unit(ranges, refid[1], refid[2])
        src == 0 && continue
        dst = get(() -> containing_unit(ranges, defid[1], defid[2]), bound, defid)
        (dst == 0 || dst == src) && continue
        out[(src, dst)] = get(out, (src, dst), 0.0) + 1.0
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
function fan_out(unit::Unit, index::QueryIndex)
    isempty(index.callee.nodes) && return 0
    span = unit_span(unit)
    for (i, u) in enumerate(units(index))
        unit_span(u) == span && return length(callees_by_unit(index)[i])
    end
    return 0
end

# Each unit's distinct callee names from one pass over the `@callee` captures, in
# `units(index)` order. The single source of what counts as a unit's callee:
# a call is attributed to its innermost unit, and a unit's own name never counts.
# `fan_out` reads one entry; the reimplementation fingerprints read them all.
function callees_by_unit(index::QueryIndex)
    units = index.units
    out = [Set{String}() for _ in units]
    isempty(index.callee.nodes) && return out
    ranges = unit_ranges(index)
    for n in index.callee.nodes
        nid = nodeid(n)
        ui = containing_unit(ranges, nid[1], nid[2])
        ui == 0 && continue
        name = String(strip(TreeSitter.slice(index.source, n)))
        isempty(name) && continue
        push!(out[ui], name)
    end
    for (i, u) in enumerate(units)
        delete!(out[i], unit_name(u, index))
    end
    return out
end
