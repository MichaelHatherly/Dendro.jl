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

# NPath grows multiplicatively and overflows fast; PMD's int version produced false
# negatives when a huge method wrapped below the threshold. The count saturates here
# instead. Inputs stay at or below the cap, so one more multiply (cap^2 < typemax)
# never overflows before clamping.
const NPATH_CAP = 1_000_000_000

# Clamp at the cap. The two differ only in the operator, so they share a structural
# shape with nothing to extract.
# dendro-ignore: duplicate
sat_mul(a::Int, b::Int) = min(NPATH_CAP, a * b)
sat_add(a::Int, b::Int) = min(NPATH_CAP, a + b)

# True when `node`'s subtree holds a `@body` block, the mark of a branch (a then/else
# arm, a loop body, a case) as opposed to a condition. Nested callables are their own
# units, so a closure body in a condition does not make the condition a branch.
function holds_body(node::TreeSitter.Node, index::QueryIndex)
    node in index.body && return true
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        holds_body(c, index) && return true
    end
    return false
end

# Number of short-circuit operators in `node`'s subtree, the `B(c)` a control
# statement's condition contributes to NPath: each `&&`/`||` adds one path.
function short_circuit_count(node::TreeSitter.Node, index::QueryIndex)
    n = node in index.short_circuit ? 1 : 0
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        n += short_circuit_count(c, index)
    end
    return n
end

# The nearest direct child of `node` that is an `if`, or `nothing`. A C-style
# `else if` nests the next `if` directly under an else clause; a Julia `else` whose
# body merely contains an `if` does not, so only direct children count.
function direct_child_if(node::TreeSitter.Node, index::QueryIndex)
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        c in index.conditional && return c
    end
    return nothing
end

"""
    npath(node, index) -> Int

NPath complexity: the number of acyclic execution paths through the unit, after
Nejmeh's measure as PMD computes it. Statement sequences multiply, branches add, and
each `&&`/`||` in a condition adds one path. Dispatches on construct family from the
query, so the arithmetic is the same across languages. Saturates at `NPATH_CAP`.
"""
function npath(node::TreeSitter.Node, index::QueryIndex)
    node in index.loop && return loop_npath(node, index)
    node in index.switch && return switch_npath(node, index)
    node in index.ternary && return ternary_npath(node, index)
    node in index.try_stmt && return try_npath(node, index)
    node in index.conditional && return if_npath(node, index)
    return sequence_npath(node, index)
end

# A sequence or any node without its own rule: the product of its children, a leaf
# being one. Nested callables are skipped, scored as their own units.
function sequence_npath(node::TreeSitter.Node, index::QueryIndex)
    p = 1
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        p = sat_mul(p, npath(c, index))
    end
    return p
end

# `if`: NP(then) + NP(each alternative) + B(conditions), plus one for the
# fall-through when no unconditional else closes the chain. An `else if` (a nested
# `if`, or an else clause wrapping one) carries its own fall-through, so the outer
# `if` adds none. Handles both the flat chain (Julia `elseif_clause`/`else_clause`
# siblings) and the nested chain (the alternative is itself an `if`).
function if_npath(node::TreeSitter.Node, index::QueryIndex)
    np = 0
    b = 0
    seen_then = false
    has_else = false
    delegated = false
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        if !holds_body(c, index)
            b = sat_add(b, short_circuit_count(c, index))
        elseif c in index.continuation
            np = sat_add(np, clause_npath(c, index))
        elseif c in index.conditional
            np = sat_add(np, npath(c, index))
            delegated = true
        elseif !seen_then
            np = sat_add(np, npath(c, index))
            seen_then = true
        else
            inner = direct_child_if(c, index)
            if inner === nothing
                np = sat_add(np, npath(c, index))
                has_else = true
            else
                np = sat_add(np, npath(inner, index))
                delegated = true
            end
        end
    end
    np = sat_add(np, b)
    (has_else || delegated) || (np = sat_add(np, 1))
    return np
end

# Fold a control node's children into (branch paths, condition B): each child holding
# a `@body` is a branch, its NPath folded with `combine` from `init`; each other child
# is condition, its short-circuit operators summed. The shared shape behind the loop,
# switch, and elseif rules.
function fold_branches(node::TreeSitter.Node, index::QueryIndex, combine::F, init::Int) where {F}
    branch = init
    b = 0
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        if holds_body(c, index)
            branch = combine(branch, npath(c, index))
        else
            b = sat_add(b, short_circuit_count(c, index))
        end
    end
    return branch, b
end

# An `elseif_clause`: its condition's `B` plus the NPath of its body, the same arm an
# `if`'s then-branch is, without the fall-through the chain accounts for once. Shares
# its combine-then-total shape with `switch_npath`.
# dendro-ignore: duplicate, near_duplicate
function clause_npath(node::TreeSitter.Node, index::QueryIndex)
    branch, b = fold_branches(node, index, sat_mul, 1)
    return sat_add(branch, b)
end

# A loop: NP(body) + B(condition) + 1 for the path that skips the loop. A for-each has
# no boolean guard, so `B` is zero and it reduces to NP(body) + 1.
function loop_npath(node::TreeSitter.Node, index::QueryIndex)
    branch, b = fold_branches(node, index, sat_mul, 1)
    return sat_add(sat_add(branch, b), 1)
end

# A switch: the sum of its case-body NPaths plus the test's `B`, no implicit
# fall-through path.
# dendro-ignore: duplicate, near_duplicate
function switch_npath(node::TreeSitter.Node, index::QueryIndex)
    branch, b = fold_branches(node, index, sat_add, 0)
    return sat_add(branch, b)
end

# A ternary `c ? a : b`: NP(a) + NP(b) + B(c). The first named child is the
# condition; the rest are the two result expressions.
function ternary_npath(node::TreeSitter.Node, index::QueryIndex)
    parts = 0
    b = 0
    seen_cond = false
    for c in TreeSitter.named_children(node)
        is_function(c, index) && continue
        if !seen_cond
            b = sat_add(b, short_circuit_count(c, index))
            seen_cond = true
        else
            parts = sat_add(parts, npath(c, index))
        end
    end
    return sat_add(parts, b)
end

# A try: NP(try-block) + the NPath of each catch and finally block. Every body-bearing
# arm adds its paths; the clauses carry no boolean guard, so `B` is dropped.
try_npath(node::TreeSitter.Node, index::QueryIndex) =
    first(fold_branches(node, index, sat_add, 0))

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
