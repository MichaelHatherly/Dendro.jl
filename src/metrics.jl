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

# Fold a metric over a unit's subtree without descending into nested callables.
# `step(node, index, ctx)` returns this node's value and the context handed to its
# children; child results merge into the parent's with `combine` (`+` or `max`).
# `step` is a plain function, never a capturing closure, so the accumulator and the
# index stay concretely typed for both inference and JET.
function fold_unit(step::S, combine::C, node::TreeSitter.Node, index::QueryIndex, ctx) where {S, C}
    value, child_ctx = step(node, index, ctx)
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        value = combine(value, fold_unit(step, combine, c, index, child_ctx))
    end
    return value
end

# Sum a counting `step` over a unit's subtree, the shape every count metric folds.
sum_over(step::S, node::TreeSitter.Node, index::QueryIndex) where {S} =
    fold_unit(step, +, node, index, nothing)

# A counting step's result: one when `hit`, else zero, with `ctx` passed through.
count_if(hit::Bool, ctx) = (hit ? 1 : 0), ctx

"""
    function_length(unit) -> Int

Number of source lines the function spans, inclusive.
"""
function_length(unit::FunctionUnit) = unit.lastline - unit.firstline + 1

"""
    parameter_count(node, index) -> Int

Number of parameters in the function's signature, taken as the named children of
the first parameter-list node the query tagged.
"""
# First parameter-list node in pre-order, or `nothing`. Descends the whole tree, so
# the outer function's signature is found before any nested callable's.
function first_parameter_list(node::TreeSitter.Node, index::QueryIndex)
    node in index.parameter && return node
    for c in TreeSitter.children(node)
        found = first_parameter_list(c, index)
        found === nothing || return found
    end
    return nothing
end

function parameter_count(node::TreeSitter.Node, index::QueryIndex)
    container = first_parameter_list(node, index)
    container === nothing && return 0
    return TreeSitter.count_named_nodes(container)
end

"""
    nesting_depth(node, index) -> Int

Maximum depth of nested control constructs within `node`'s subtree. A function body
with no control flow has depth 0.
"""
nesting_depth(node::TreeSitter.Node, index::QueryIndex) =
    fold_unit(nesting_step, max, node, index, 0)

# Depth at `node` is the enclosing depth plus one for a nesting construct; children
# inherit it, and `max` keeps the deepest.
function nesting_step(node::TreeSitter.Node, index::QueryIndex, depth::Int)
    here = node in index.nesting ? depth + 1 : depth
    return here, here
end

# True when `n` adds an independent path: a decision-point node, or a short-circuit
# operator (each `&&`/`||` forks the flow).
is_branch_point(n::TreeSitter.Node, index::QueryIndex) =
    n in index.decision || n in index.short_circuit

"""
    cyclomatic(node, index) -> Int

McCabe cyclomatic complexity: one plus the number of branch points in `node`'s
subtree. Branch points are the query's decision points plus short-circuit operators
(`&&`, `||`), which each add an independent path.
"""
cyclomatic(node::TreeSitter.Node, index::QueryIndex) =
    1 + sum_over(branch_step, node, index)

# The counting steps are each one `count_if` over a different predicate, so they
# share a shape with nothing to extract.
# dendro-ignore: duplicate
branch_step(node::TreeSitter.Node, index::QueryIndex, ctx) =
    count_if(is_branch_point(node, index), ctx)

"""
    return_count(node, index) -> Int

Number of return statements in the unit. A language with no return-statement node,
or one whose idiomatic return is a bare expression, counts only explicit returns.
"""
return_count(node::TreeSitter.Node, index::QueryIndex) =
    sum_over(return_step, node, index)

return_step(node::TreeSitter.Node, index::QueryIndex, ctx) =
    count_if(node in index.return_stmt, ctx)

# The short-circuit operator joining `node`'s direct children, or `nothing`. A
# boolean expression node carries its operator as a child; this returns its text.
function op_child_text(node::TreeSitter.Node, index::QueryIndex)
    for c in TreeSitter.children(node)
        c in index.short_circuit || continue
        return String(strip(TreeSitter.slice(index.source, c)))
    end
    return nothing
end

# True when `node` has a direct child that is a short-circuit operator, so it is the
# root of one `&&`/`||` link in a boolean expression.
has_op_child(node::TreeSitter.Node, index::QueryIndex) =
    op_child_text(node, index) !== nothing

# Number of operator nodes in `node`'s subtree, the size of one connected boolean
# expression once `node` is its top.
# The `sum_over` count metrics share a one-line shape over different steps; this one
# collides exactly with `return_count` and near with `cyclomatic`.
# dendro-ignore: duplicate, near_duplicate
count_op_nodes(node::TreeSitter.Node, index::QueryIndex) =
    sum_over(op_count_step, node, index)

op_count_step(node::TreeSitter.Node, index::QueryIndex, ctx) =
    count_if(has_op_child(node, index), ctx)

"""
    boolean_complexity(node, index) -> Int

The most short-circuit operators (`&&`, `||`) joined into a single boolean
expression in the unit. `a && b && c` scores 2; two separate two-operator
conditions score 2, not 4.
"""
function boolean_complexity(node::TreeSitter.Node, index::QueryIndex)
    isempty(index.short_circuit.ids) && return 0
    return fold_unit(op_chain_step, max, node, index, nothing)
end

# The top of an expression owns its whole subtree's operators; a nested operator node
# counts a strict subset, so `max` selects the outermost. Separate expressions compete.
op_chain_step(node::TreeSitter.Node, index::QueryIndex, ctx) =
    (has_op_child(node, index) ? count_op_nodes(node, index) : 0), ctx

# Number of maximal same-operator runs of short-circuit operators in the unit. A run
# is an unbroken chain of one operator; `a && b && c` is one run, `a && b || c` two.
function boolean_runs(node::TreeSitter.Node, index::QueryIndex)
    isempty(index.short_circuit.ids) && return 0
    return fold_unit(op_run_step, +, node, index, "")
end

# The context is the operator of the nearest enclosing operator node (`""` for none);
# a node starts a new run when its own operator differs, and becomes that context for
# its children.
function op_run_step(node::TreeSitter.Node, index::QueryIndex, parent_op::String)
    op = op_child_text(node, index)
    op === nothing && return 0, parent_op
    return (op == parent_op ? 0 : 1), op
end

"""
    cognitive_complexity(node, index) -> Int

A structural reading of how hard a function is to follow, after SonarSource's
Cognitive Complexity. Each decision point adds one plus the nesting it sits under,
so a branch three levels deep costs more than a flat one of the same cyclomatic
count. An else-if continuation adds a flat one instead, since it reads at the same
level as the `if` it extends. Each maximal run of one short-circuit operator adds
one; an operator change starts a new run.
"""
cognitive_complexity(node::TreeSitter.Node, index::QueryIndex) =
    fold_unit(cognitive_step, +, node, index, 0) + boolean_runs(node, index)

# A decision adds one plus its enclosing nesting; an else-if continuation adds a flat
# one; a nesting construct deepens the context for its children.
function cognitive_step(node::TreeSitter.Node, index::QueryIndex, nesting::Int)
    score = node in index.continuation ? 1 :
        node in index.decision ? 1 + nesting : 0
    child_nesting = node in index.nesting ? nesting + 1 : nesting
    return score, child_nesting
end
