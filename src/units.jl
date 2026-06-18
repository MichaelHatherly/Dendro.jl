# Function-unit access. A unit is one callable body, the granularity at which
# metrics are reported. The units themselves are identified by the language query
# and carried on the [`QueryIndex`](@ref); this layer exposes them and the
# membership test scoring uses to stop at a nested callable.

"""
    functions(index) -> Vector{FunctionUnit}

Every callable definition the language query found, in source order.
"""
functions(index::QueryIndex) = index.functions

"""
    is_function(node, index) -> Bool

True when `node` is one of the callable definitions the query tagged: a
`function ... end` or a short-form `f(x) = expr` whose left side resolves to a call
signature. This is the no-descend boundary for unit-scoped metrics and clone
detection.
"""
# A one-line `hasid` membership test like `Base.in(::Node, ::Concept)`; the verbose
# typed signatures collide structurally with nothing to extract.
# dendro-ignore: near_duplicate
is_function(node::TreeSitter.Node, index::QueryIndex) = hasid(index.function_ids, node)
