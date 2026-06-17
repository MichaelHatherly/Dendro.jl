# Scalar metrics over a function unit's subtree.

# Absolute severity bands per metric, as (warn, high) lower bounds. A value at
# or above `high` is `:high`, at or above `warn` is `:warn`, else `:ok`. These
# are fixed targets, so a uniformly-weak codebase has a standard to improve
# toward rather than only its own median. Drawn from common complexity guidance.
const DEFAULT_BANDS = Dict{Symbol,Tuple{Int,Int}}(
    :cyclomatic => (11, 21),
    :function_length => (50, 100),
    :nesting_depth => (4, 6),
    :parameter_count => (5, 8),
)

"""
    severity(metric, value; bands=DEFAULT_BANDS) -> Symbol

Classify `value` for `metric` against its absolute band as `:ok`, `:warn`, or
`:high`.
"""
function severity(metric::Symbol, value::Real; bands=DEFAULT_BANDS)
    warn, high = bands[metric]
    return value >= high ? :high : value >= warn ? :warn : :ok
end

# Metric names carried in baselines and findings, in report order.
const SCALAR_METRICS = (:cyclomatic, :function_length, :nesting_depth, :parameter_count)

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
    unit_metrics(unit, profile, source) -> NamedTuple

All scalar metrics for one function unit, keyed by metric name.
"""
function unit_metrics(unit::FunctionUnit, profile::LanguageProfile, source::AbstractString)
    return (
        cyclomatic = cyclomatic(unit.node, profile, source),
        function_length = function_length(unit),
        nesting_depth = nesting_depth(unit.node, profile),
        parameter_count = parameter_count(unit.node, profile),
    )
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
