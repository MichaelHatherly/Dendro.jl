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
function functions(tree, profile::LanguageProfile)
    units = FunctionUnit[]
    TreeSitter.traverse(tree) do node, enter
        if enter && TreeSitter.node_type(node) in profile.function_types
            sp = TreeSitter.start_point(node)
            ep = TreeSitter.end_point(node)
            push!(units, FunctionUnit(node, Int(sp.row) + 1, Int(ep.row) + 1))
        end
        nothing
    end
    return units
end
