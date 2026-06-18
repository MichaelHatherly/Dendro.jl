# Function-unit extraction. A unit is one callable body, the granularity at
# which metrics are reported.

"""
    FunctionUnit

A single callable definition: the tree-sitter node plus its 1-based first and
last source line.
"""
struct FunctionUnit
    node::TreeSitter.Node
    firstline::Int
    lastline::Int
end

"""
    functions(tree, profile) -> Vector{FunctionUnit}

Collect every callable definition in `tree` whose node type the `profile`
recognises.
"""
function functions(tree::TreeSitter.Tree, profile::LanguageProfile)
    units = FunctionUnit[]
    for node in collect_tree(is_function_node, tree, profile, "")
        sp = TreeSitter.start_point(node)
        ep = TreeSitter.end_point(node)
        push!(units, FunctionUnit(node, Int(sp.row) + 1, Int(ep.row) + 1))
    end
    return units
end

is_function_node(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    is_function(node, profile)

"""
    is_function(node, profile) -> Bool

True when `node` is a function definition: a `function ... end`
(`profile.function_types`), or a short-form `f(x) = expr`
(`profile.short_function_types`) whose assignment left side resolves to a call
signature. The unwrap step strips `profile.signature_wrapper_types` (`f(x)::T`,
`f(x) where {T}`), so a plain `x = e` or a typed keyword default `k::T = e`, whose
left side never reaches a call, is not a definition.
"""
function is_function(node::TreeSitter.Node, profile::LanguageProfile)
    TreeSitter.node_type(node) in profile.function_types && return true
    TreeSitter.node_type(node) in profile.short_function_types || return false
    lhs = first_named_child(node)
    while lhs !== nothing && TreeSitter.node_type(lhs) in profile.signature_wrapper_types
        lhs = first_named_child(lhs)
    end
    return lhs !== nothing && TreeSitter.node_type(lhs) in profile.signature_types
end

# First named child of `node`, or `nothing`.
function first_named_child(node::TreeSitter.Node)
    for c in TreeSitter.children(node)
        TreeSitter.is_named(c) && return c
    end
    return nothing
end
