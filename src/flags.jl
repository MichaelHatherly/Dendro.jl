# Flag metrics: presence is the finding, no distribution. These target failure
# modes common in generated code, swallowed errors and unfinished stubs.

const STUB_PATTERN = r"\b(?:TODO|FIXME|XXX|HACK)\b"i

# Operators where two equal operands are ordinary, not a mistake: doubling (`x + x`),
# scaling (`x * x`), shifts, the `x != x` NaN check, and `=>` pair construction,
# where an identity entry (`"Accept" => "Accept"`) is a canonicalisation table, not a
# redundant comparison.
const IDEMPOTENT_OPS = Set{String}(["+", "*", "**", "<<", ">>", "!=", "!==", "=>"])

# Source text of a node with runs of whitespace collapsed, for exact-match
# comparison that tolerates reformatting but not a renamed identifier or literal.
normalized_text(node::TreeSitter.Node, source::AbstractString) =
    replace(strip(TreeSitter.slice(source, node)), r"\s+" => " ")

# First direct child of `node` that the query tagged for `concept`, or `nothing`.
function first_child_in(node::TreeSitter.Node, concept::Concept)
    for c in TreeSitter.children(node)
        c in concept && return c
    end
    return nothing
end

# Named children of a body that do real work, ignoring no-op statements like
# `pass`. A body is effectively empty when this count is zero.
function nontrivial_count(body::TreeSitter.Node, index::QueryIndex)
    n = 0
    for c in TreeSitter.children(body)
        TreeSitter.is_named(c) || continue
        c in index.trivial_body || (n += 1)
    end
    return n
end

# True when a body node is missing or does no real work.
function empty_block(body, index::QueryIndex)
    body === nothing && return true
    return nontrivial_count(body, index) == 0
end

# Last named child of `node`, or `nothing`.
function last_named_child(node::TreeSitter.Node)
    last = nothing
    for c in TreeSitter.children(node)
        TreeSitter.is_named(c) && (last = c)
    end
    return last
end

# A function's body: its block child (`function ... end`), or the right-hand
# expression of a short-form `f(x) = expr`. `nothing` for a function with neither,
# a genuinely bodyless declaration.
function function_body(node::TreeSitter.Node, index::QueryIndex)
    block = first_child_in(node, index.body)
    block === nothing || return block
    # A short form has no block; its body is the right-hand side. A block-less
    # function that is not a short form (an abstract method) is genuinely bodyless.
    node in index.short_function || return nothing
    return last_named_child(node)
end

"""
    empty_body(node, index) -> Bool

True when the function `node` has no body, or a block body that does no real work. A
short-form `f(x) = expr` has an expression body, which always does work, so it is
never empty.
"""
function empty_body(node::TreeSitter.Node, index::QueryIndex)
    body = function_body(node, index)
    body === nothing && return true
    body in index.body && return empty_block(body, index)
    return false
end

"""
    is_identical_operands(node, index) -> Bool

True when `node` is a binary expression whose two operands are textually identical,
like `x == x` or `a && a`. The duplication is almost always a mistake: a comparison
that is always true or false, a redundant boolean. Operators where equal operands
are ordinary (`+`, `*`, shifts, `!=` for a NaN check, `=>` for an identity pair in a
canonicalisation table) are left alone. A chained
comparison (`a == b == c`) is one n-ary node, not a binary pair, so it never matches.
The `:identical_operands` rule reports one finding per match.
"""
function is_identical_operands(node::TreeSitter.Node, index::QueryIndex)
    source = index.source
    # Julia carries the operator as a named child of the expression; every other
    # grammar leaves it anonymous. Excluding tagged operators leaves the operands, so
    # a true binary has exactly two and an n-ary chain has three or more. A plain loop
    # rather than a comprehension keeps `index` out of a capturing closure.
    operands = TreeSitter.Node[]
    for c in TreeSitter.named_children(node)
        c in index.operator || push!(operands, c)
    end
    return length(operands) == 2 &&
        normalized_text(first(operands), source) == normalized_text(last(operands), source) &&
        !any(c -> normalized_text(c, source) in IDEMPOTENT_OPS, TreeSitter.children(node))
end

# Body blocks belonging to one conditional: those directly under it and under its
# continuation clauses (else, elseif, case), but not those inside a nested
# conditional, loop, or function. Conservative by design: a chain a grammar nests
# rather than flattens (an `else if` parsed as an `if` inside an `else`) yields only
# the branches reachable without crossing a fresh construct.
function branch_blocks(node::TreeSitter.Node, index::QueryIndex)
    blocks = TreeSitter.Node[]
    collect_branch_blocks!(blocks, node, index)
    return blocks
end

function collect_branch_blocks!(blocks, node::TreeSitter.Node, index::QueryIndex)
    for c in TreeSitter.children(node)
        if c in index.body
            push!(blocks, c)
        elseif is_function(c, index) || c in index.nesting
            continue
        else
            collect_branch_blocks!(blocks, c, index)
        end
    end
    return blocks
end

"""
    is_duplicate_branches(node, index) -> Bool

True when `node` is a conditional whose branches are all textually identical: every
arm of an `if`/`else` chain runs the same code, so the condition decides nothing. At
least two arms must be present to compare. The `:duplicate_branches` rule reports one
finding per match. A `switch`/`case` is not compared: its arms carry their statements
directly, with no per-arm body block to set against each other.
"""
function is_duplicate_branches(node::TreeSitter.Node, index::QueryIndex)
    blocks = branch_blocks(node, index)
    length(blocks) >= 2 || return false
    texts = [normalized_text(b, index.source) for b in blocks]
    return all(==(first(texts)), texts)
end

# Tagged nodes of one concept that `pred` accepts, the shape every node-filtering
# flag rule shares.
filter_nodes(pred::P, concept::Concept, index::QueryIndex) where {P} =
    [n for n in concept.nodes if pred(n, index)]

"""
    identical_operands(index) -> Vector{TreeSitter.Node}

Binary expressions whose two operands are textually identical.
"""
# The node-filtering flag rules are each one `filter_nodes` call over a different
# concept and predicate, so they share a shape with nothing left to extract.
# dendro-ignore: duplicate
identical_operands(index::QueryIndex) =
    filter_nodes(is_identical_operands, index.binary_expr, index)

"""
    duplicate_branches(index) -> Vector{TreeSitter.Node}

Conditionals whose branches are all textually identical.
"""
duplicate_branches(index::QueryIndex) =
    filter_nodes(is_duplicate_branches, index.conditional, index)

"""
    unreachable_statements(index) -> Vector{TreeSitter.Node}

Statements that follow an unconditional control-flow terminator (`return`, `break`,
`throw`) in the same block, and so can never run. One finding per block, anchored on
the first dead statement.
"""
function unreachable_statements(index::QueryIndex)
    out = TreeSitter.Node[]
    for body in index.body.nodes
        terminated = false
        for c in TreeSitter.children(body)
            (TreeSitter.is_named(c) && !(c in index.comment)) || continue
            if terminated && !(c in index.trivial_body)
                push!(out, c)
                break
            end
            c in index.terminal && (terminated = true)
        end
    end
    return out
end

"""
    empty_bodies(index) -> Vector{TreeSitter.Node}

Function nodes with no body, or a body that does no real work.
"""
empty_bodies(index::QueryIndex) =
    [u.node for u in functions(index) if empty_body(u.node, index)]

"""
    empty_catches(index) -> Vector{TreeSitter.Node}

Exception-handling clauses with an empty or absent body, which swallow errors.
"""
empty_catches(index::QueryIndex) =
    [n for n in index.catch_clause.nodes if empty_block(first_child_in(n, index.body), index)]

"""
    stub_markers(index) -> Vector{TreeSitter.Node}

Comment nodes carrying a stub marker (`TODO`, `FIXME`, `XXX`, `HACK`).
"""
stub_markers(index::QueryIndex) =
    [n for n in index.comment.nodes if occursin(STUB_PATTERN, TreeSitter.slice(index.source, n))]

"""
    returns_in_finally(index) -> Vector{TreeSitter.Node}

Return statements inside a finally/ensure clause, which discard a pending exception
or return value. Empty for a language with no finally construct.
"""
returns_in_finally(index::QueryIndex) =
    filter_nodes(is_return_in_finally, index.return_stmt, index)

# A return whose nearest enclosing finally/function ancestor is a finally. Walking up
# `parent`, a finally seen before any function means the return runs in that finally;
# a function seen first means the return belongs to a nested callable, excluded. This
# matches a "stop at a nested callable" descent exactly.
function is_return_in_finally(node::TreeSitter.Node, index::QueryIndex)
    p = TreeSitter.parent(node)
    while !TreeSitter.is_null(p)
        p in index.finally_clause && return true
        is_function(p, index) && return false
        p = TreeSitter.parent(p)
    end
    return false
end

# True when a statement is, or directly wraps, a single call: a bare call, or a
# return/expression statement whose only named child is a call.
function single_call(stmt::TreeSitter.Node, index::QueryIndex)
    stmt in index.call && return true
    kids = collect(TreeSitter.named_children(stmt))
    return length(kids) == 1 && only(kids) in index.call
end

"""
    trivial_wrappers(index) -> Vector{TreeSitter.Node}

Function nodes whose body is one delegating call, an indirection that adds no
behaviour. Empty for a language with no call-expression concept.
"""
function trivial_wrappers(index::QueryIndex)
    out = TreeSitter.Node[]
    isempty(index.call.ids) && return out
    for u in functions(index)
        body = function_body(u.node, index)
        body === nothing && continue
        if body in index.body
            stmts = [
                c for c in TreeSitter.children(body)
                    if TreeSitter.is_named(c) && !(c in index.trivial_body)
            ]
            length(stmts) == 1 && single_call(only(stmts), index) && push!(out, u.node)
        else
            single_call(body, index) && push!(out, u.node)
        end
    end
    return out
end
