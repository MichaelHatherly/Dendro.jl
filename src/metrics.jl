# Scalar metrics over a function unit's subtree.

"""
    severity(value, band) -> Symbol

Classify `value` against its `(warn, high)` `band`: `:high` at or above `high`,
`:warn` at or above `warn`, else `:ok`.
"""
function severity(value::Real, band::Tuple{Int,Int})
    warn, high = band
    return value >= high ? :high : value >= warn ? :warn : :ok
end

# Depth-first over `node`'s own subtree, calling `f(n, enter)` on enter and exit
# like `TreeSitter.traverse`, but never descending into a nested callable: each
# is reported as its own unit, so its complexity stays out of the enclosing one.
function traverse_unit(f, node::TreeSitter.Node, profile::LanguageProfile)
    f(node, true)
    for c in TreeSitter.children(node)
        TreeSitter.node_type(c) in profile.function_types && continue
        traverse_unit(f, c, profile)
    end
    f(node, false)
    return nothing
end

"""
    function_length(unit) -> Int

Number of source lines the function spans, inclusive.
"""
function_length(unit::FunctionUnit) = unit.lastline - unit.firstline + 1

"""
    parameter_count(node, profile) -> Int

Number of parameters in the function's signature, taken as the named children
of the first parameter-list node (`profile.parameter_types`).
"""
function parameter_count(node::TreeSitter.Node, profile::LanguageProfile)
    container = nothing
    TreeSitter.traverse(node) do n, enter
        if enter && container === nothing && TreeSitter.node_type(n) in profile.parameter_types
            container = n
        end
        nothing
    end
    container === nothing && return 0
    return TreeSitter.count_named_nodes(container)
end

"""
    nesting_depth(node, profile) -> Int

Maximum depth of nested control constructs (`profile.nesting_types`) within
`node`'s subtree. A function body with no control flow has depth 0.
"""
function nesting_depth(node::TreeSitter.Node, profile::LanguageProfile)
    maxdepth = 0
    depth = 0
    traverse_unit(node, profile) do n, enter
        if TreeSitter.is_named(n) && TreeSitter.node_type(n) in profile.nesting_types
            if enter
                depth += 1
                depth > maxdepth && (maxdepth = depth)
            else
                depth -= 1
            end
        end
        nothing
    end
    return maxdepth
end

"""
    cyclomatic(node, profile, source) -> Int

McCabe cyclomatic complexity: one plus the number of branch points in `node`'s
subtree. Branch points are the profile's `decision_types` plus short-circuit
operators (`&&`, `||`), which each add an independent path.
"""
function cyclomatic(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    count = 1
    has_ops = !isempty(profile.short_circuit_ops)
    traverse_unit(node, profile) do n, enter
        if enter
            if TreeSitter.is_named(n) && TreeSitter.node_type(n) in profile.decision_types
                count += 1
            elseif has_ops &&
                   TreeSitter.is_leaf(n) &&
                   strip(TreeSitter.slice(source, n)) in profile.short_circuit_ops
                count += 1
            end
        end
        nothing
    end
    return count
end

"""
    return_count(node, profile) -> Int

Number of return statements (`profile.return_types`) in the unit. A language with
no return-statement node, or one whose idiomatic return is a bare expression,
counts only explicit returns.
"""
function return_count(node::TreeSitter.Node, profile::LanguageProfile)
    count = 0
    traverse_unit(node, profile) do n, enter
        enter && TreeSitter.node_type(n) in profile.return_types && (count += 1)
        nothing
    end
    return count
end

# True when `node` has a direct child that is a short-circuit operator leaf, so it
# is the root of one `&&`/`||` link in a boolean expression.
function has_op_child(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    for c in TreeSitter.children(node)
        TreeSitter.is_leaf(c) || continue
        strip(TreeSitter.slice(source, c)) in profile.short_circuit_ops && return true
    end
    return false
end

# Number of operator nodes in `node`'s subtree, the size of one connected boolean
# expression once `node` is its top.
function count_op_nodes(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    count = 0
    traverse_unit(node, profile) do n, enter
        enter && has_op_child(n, profile, source) && (count += 1)
        nothing
    end
    return count
end

"""
    boolean_complexity(node, profile, source) -> Int

The most short-circuit operators (`&&`, `||`) joined into a single boolean
expression in the unit. `a && b && c` scores 2; two separate two-operator
conditions score 2, not 4.
"""
function boolean_complexity(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    isempty(profile.short_circuit_ops) && return 0
    best = 0
    depth = 0
    traverse_unit(node, profile) do n, enter
        if has_op_child(n, profile, source)
            if enter
                depth == 0 && (best = max(best, count_op_nodes(n, profile, source)))
                depth += 1
            else
                depth -= 1
            end
        end
        nothing
    end
    return best
end
