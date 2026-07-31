# Unit access. A unit is the granularity metrics are reported at: a run of sibling
# nodes, which for a callable is the run of one node the language query tagged. The
# units are carried on the [`QueryIndex`](@ref); this layer exposes them, the span a
# run covers, and the membership test scoring uses to stop at a nested callable.

"""
    units(index) -> Vector{Unit}

Every unit the language query found, in source order.
"""
units(index::QueryIndex) = index.units

"""
    unit_span(unit) -> (from, to)

The byte range a unit covers, the start of its first node to the end of its last.
A run of one node is that node's own range.
"""
unit_span(u::Unit) =
    (TreeSitter.byte_range(first(u.nodes))[1], TreeSitter.byte_range(last(u.nodes))[2])

"""
    unit_node(unit) -> TreeSitter.Node

The node a callable unit is defined by. Only meaningful for a run of one: the
signature-shaped readings (`parameter_count`, `function_body`, the unit's name) ask
about a definition, and a run of several is top-level code with no definition to ask
about.
"""
unit_node(u::Unit) = first(u.nodes)

"""
    is_callable(unit, index) -> Bool

Whether a unit is a definition rather than top-level code. A callable is the run of
one node the query tagged `@function`; a run of several is a stretch of top-level
statements, which has no signature and no boundary an author drew.
"""
is_callable(u::Unit, index::QueryIndex) =
    length(u.nodes) == 1 && is_function(only(u.nodes), index)

"""
    is_function(node, index) -> Bool

True when `node` is one of the callable definitions the query tagged: a
`function ... end` or a short-form `f(x) = expr` whose left side resolves to a call
signature. This is the no-descend boundary for unit-scoped metrics and clone
detection.
"""
# A one-line `hasid` membership test like `Base.in(::Node, ::Concept)`; the verbose
# typed signatures collide structurally with nothing to extract.
is_function(node::TreeSitter.Node, index::QueryIndex) = hasid(index.function_ids, node)

# The defining name tagged on `node`'s binder, a sibling outside its subtree, or "".
# An anonymous callable bound to a name (a JS arrow `const f = () => ...`) carries its
# name on the enclosing binder, so a unit holding no name of its own takes the binder's.
function binder_def_name(node::TreeSitter.Node, index::QueryIndex)
    p = TreeSitter.parent(node)
    TreeSitter.is_null(p) && return ""
    for c in TreeSitter.children(p)
        c in index.def_name && return String(strip(TreeSitter.slice(index.source, c)))
    end
    return ""
end

# Label a function node by its name, or "" when no name node is found. A qualified
# definition tags its final component as `def_name`; prefer that over the first
# `@name`, which for `Module.method` is the module qualifier. A bound anonymous
# callable takes the name from its enclosing binder when it holds none of its own.
function unit_name(node::TreeSitter.Node, index::QueryIndex)
    name = Ref("")
    def = Ref("")
    TreeSitter.traverse(node) do n, enter
        if enter
            isempty(name[]) && n in index.name &&
                (name[] = String(strip(TreeSitter.slice(index.source, n))))
            isempty(def[]) && n in index.def_name &&
                (def[] = String(strip(TreeSitter.slice(index.source, n))))
        end
        nothing
    end
    isempty(def[]) || return def[]
    binder = binder_def_name(node, index)
    return isempty(binder) ? name[] : binder
end

unit_name(unit::Unit, index::QueryIndex) = unit_name(unit_node(unit), index)
