# Scalar metrics over a function unit's subtree.

"""
    severity(value, band) -> Symbol

Classify `value` against its `(warn, high)` `band`: `:high` at or above `high`,
`:warn` at or above `warn`, else `:ok`.
"""
function severity(value::Real, band::Tuple{Int, Int})
    warn, high = band
    return value >= high ? :high : value >= warn ? :warn : :ok
end

# Every node (pre-order, full descent) for which `match` holds. `match` is a plain
# function, never a capturing closure, so profile and source stay concretely typed
# for both inference and JET.
function collect_tree(match::M, tree::TreeSitter.Tree, profile::LanguageProfile, source::AbstractString) where {M}
    out = TreeSitter.Node[]
    collect_tree!(out, match, TreeSitter.root(tree), profile, source)
    return out
end

function collect_tree!(out::Vector{TreeSitter.Node}, match::M, node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) where {M}
    match(node, profile, source) && push!(out, node)
    for c in TreeSitter.children(node)
        collect_tree!(out, match, c, profile, source)
    end
    return out
end

# Every node (pre-order, full descent) whose type is in `types`. A type-membership
# walk, factored out so a metric that only needs "all nodes of these types" does not
# repeat a one-line predicate, which short-form recognition would read as a clone.
function collect_typed(tree::TreeSitter.Tree, profile::LanguageProfile, types::Set{String})
    out = TreeSitter.Node[]
    collect_typed!(out, TreeSitter.root(tree), types)
    return out
end

function collect_typed!(out::Vector{TreeSitter.Node}, node::TreeSitter.Node, types::Set{String})
    TreeSitter.node_type(node) in types && push!(out, node)
    for c in TreeSitter.children(node)
        collect_typed!(out, c, types)
    end
    return out
end

# Fold a metric over a unit's subtree without descending into nested callables.
# `step(node, profile, source, ctx)` returns this node's value and the context handed
# to its children; child results merge into the parent's with `combine` (`+` or `max`).
# `step` is a plain function, never a capturing closure, so the accumulator and the
# profile stay concretely typed for both inference and JET.
function fold_unit(step::S, combine::C, node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, ctx) where {S, C}
    value, child_ctx = step(node, profile, source, ctx)
    for c in TreeSitter.children(node)
        is_function(c, profile) && continue
        value = combine(value, fold_unit(step, combine, c, profile, source, child_ctx))
    end
    return value
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
# First parameter-list node in pre-order, or `nothing`. Descends the whole tree,
# so the outer function's signature is found before any nested callable's.
function first_parameter_list(node::TreeSitter.Node, profile::LanguageProfile)
    TreeSitter.node_type(node) in profile.parameter_types && return node
    for c in TreeSitter.children(node)
        found = first_parameter_list(c, profile)
        found === nothing || return found
    end
    return nothing
end

function parameter_count(node::TreeSitter.Node, profile::LanguageProfile)
    container = first_parameter_list(node, profile)
    container === nothing && return 0
    return TreeSitter.count_named_nodes(container)
end

"""
    nesting_depth(node, profile) -> Int

Maximum depth of nested control constructs (`profile.nesting_types`) within
`node`'s subtree. A function body with no control flow has depth 0.
"""
nesting_depth(node::TreeSitter.Node, profile::LanguageProfile) =
    fold_unit(nesting_step, max, node, profile, "", 0)

# Depth at `node` is the enclosing depth plus one for a nesting construct; children
# inherit it, and `max` keeps the deepest.
function nesting_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, depth::Int)
    here = TreeSitter.is_named(node) && TreeSitter.node_type(node) in profile.nesting_types ?
        depth + 1 : depth
    return here, here
end

# True when `n` adds an independent path: a decision-point node, or a short-circuit
# operator leaf (each `&&`/`||` forks the flow).
function is_branch_point(n::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, has_ops::Bool)
    TreeSitter.is_named(n) && TreeSitter.node_type(n) in profile.decision_types && return true
    return has_ops && TreeSitter.is_leaf(n) &&
        strip(TreeSitter.slice(source, n)) in profile.short_circuit_ops
end

"""
    cyclomatic(node, profile, source) -> Int

McCabe cyclomatic complexity: one plus the number of branch points in `node`'s
subtree. Branch points are the profile's `decision_types` plus short-circuit
operators (`&&`, `||`), which each add an independent path.
"""
cyclomatic(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    1 + fold_unit(branch_step, +, node, profile, source, !isempty(profile.short_circuit_ops))

# The context is `has_ops`, constant through the walk.
branch_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, has_ops::Bool) =
    (is_branch_point(node, profile, source, has_ops) ? 1 : 0), has_ops

"""
    return_count(node, profile) -> Int

Number of return statements (`profile.return_types`) in the unit. A language with
no return-statement node, or one whose idiomatic return is a bare expression,
counts only explicit returns.
"""
return_count(node::TreeSitter.Node, profile::LanguageProfile) =
    fold_unit(return_step, +, node, profile, "", nothing)

return_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, ctx) =
    (TreeSitter.node_type(node) in profile.return_types ? 1 : 0), ctx

# The short-circuit operator joining `node`'s direct children, or `nothing`. A
# boolean expression node carries its operator as a leaf child; this returns its text.
function op_child_text(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    for c in TreeSitter.children(node)
        TreeSitter.is_leaf(c) || continue
        text = strip(TreeSitter.slice(source, c))
        text in profile.short_circuit_ops && return String(text)
    end
    return nothing
end

# True when `node` has a direct child that is a short-circuit operator leaf, so it
# is the root of one `&&`/`||` link in a boolean expression.
has_op_child(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    op_child_text(node, profile, source) !== nothing

# Number of operator nodes in `node`'s subtree, the size of one connected boolean
# expression once `node` is its top.
count_op_nodes(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    fold_unit(op_count_step, +, node, profile, source, nothing)

op_count_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, ctx) =
    (has_op_child(node, profile, source) ? 1 : 0), ctx

"""
    boolean_complexity(node, profile, source) -> Int

The most short-circuit operators (`&&`, `||`) joined into a single boolean
expression in the unit. `a && b && c` scores 2; two separate two-operator
conditions score 2, not 4.
"""
function boolean_complexity(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    isempty(profile.short_circuit_ops) && return 0
    return fold_unit(op_chain_step, max, node, profile, source, nothing)
end

# The top of an expression owns its whole subtree's operators; a nested operator node
# counts a strict subset, so `max` selects the outermost. Separate expressions compete.
op_chain_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, ctx) =
    (has_op_child(node, profile, source) ? count_op_nodes(node, profile, source) : 0), ctx

# Number of maximal same-operator runs of short-circuit operators in the unit. A run
# is an unbroken chain of one operator; `a && b && c` is one run, `a && b || c` two.
function boolean_runs(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    isempty(profile.short_circuit_ops) && return 0
    return fold_unit(op_run_step, +, node, profile, source, "")
end

# The context is the operator of the nearest enclosing operator node (`""` for none);
# a node starts a new run when its own operator differs, and becomes that context for
# its children.
function op_run_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, parent_op::String)
    op = op_child_text(node, profile, source)
    op === nothing && return 0, parent_op
    return (op == parent_op ? 0 : 1), op
end

"""
    cognitive_complexity(node, profile, source) -> Int

A structural reading of how hard a function is to follow, after SonarSource's
Cognitive Complexity. Each decision point (`profile.decision_types`) adds one plus
the nesting (`profile.nesting_types`) it sits under, so a branch three levels deep
costs more than a flat one of the same cyclomatic count. An else-if continuation
(`profile.continuation_types`) adds a flat one instead, since it reads at the same
level as the `if` it extends. Each maximal run of one short-circuit operator adds
one; an operator change starts a new run.
"""
cognitive_complexity(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    fold_unit(cognitive_step, +, node, profile, "", 0) + boolean_runs(node, profile, source)

# A decision adds one plus its enclosing nesting; an else-if continuation adds a flat
# one; a nesting construct deepens the context for its children. Only named nodes count.
function cognitive_step(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString, nesting::Int)
    TreeSitter.is_named(node) || return 0, nesting
    t = TreeSitter.node_type(node)
    score = t in profile.continuation_types ? 1 :
        t in profile.decision_types ? 1 + nesting : 0
    child_nesting = t in profile.nesting_types ? nesting + 1 : nesting
    return score, child_nesting
end
