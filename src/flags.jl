# Flag metrics: presence is the finding, no distribution. These target failure
# modes common in generated code, swallowed errors and unfinished stubs.

const STUB_PATTERN = r"\b(?:TODO|FIXME|XXX|HACK)\b"i

# Operators where two equal operands are ordinary, not a mistake: doubling (`x + x`),
# scaling (`x * x`), shifts, and the `x != x` NaN check.
const IDEMPOTENT_OPS = Set{String}(["+", "*", "**", "<<", ">>", "!=", "!=="])

# Source text of a node with runs of whitespace collapsed, for exact-match
# comparison that tolerates reformatting but not a renamed identifier or literal.
normalized_text(node::TreeSitter.Node, source::AbstractString) =
    replace(strip(TreeSitter.slice(source, node)), r"\s+" => " ")

# First direct child of `node` whose type is in `types`, or `nothing`.
function first_child_of(node::TreeSitter.Node, types::Set{String})
    for c in TreeSitter.children(node)
        TreeSitter.node_type(c) in types && return c
    end
    return nothing
end

# Named children of a body that do real work, ignoring no-op statements like
# `pass`. A body is effectively empty when this count is zero.
function nontrivial_count(body::TreeSitter.Node, profile::LanguageProfile)
    n = 0
    for c in TreeSitter.children(body)
        TreeSitter.is_named(c) || continue
        TreeSitter.node_type(c) in profile.trivial_body_types || (n += 1)
    end
    return n
end

# True when a body node is missing or does no real work.
function empty_block(body, profile::LanguageProfile)
    body === nothing && return true
    return nontrivial_count(body, profile) == 0
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
function function_body(node::TreeSitter.Node, profile::LanguageProfile)
    block = first_child_of(node, profile.body_types)
    block === nothing || return block
    TreeSitter.node_type(node) in profile.short_function_types || return nothing
    return last_named_child(node)
end

"""
    empty_body(node, profile) -> Bool

True when the function `node` has no body, or a block body that does no real work. A
short-form `f(x) = expr` has an expression body, which always does work, so it is
never empty.
"""
function empty_body(node::TreeSitter.Node, profile::LanguageProfile)
    body = function_body(node, profile)
    body === nothing && return true
    TreeSitter.node_type(body) in profile.body_types && return empty_block(body, profile)
    return false
end

# Nodes matching `match`, or none without descending when `types` is empty: a language
# whose grammar lacks the relevant node types can hold no match, so the walk is skipped.
function flagged_nodes(match::M, tree::TreeSitter.Tree, profile::LanguageProfile, source::AbstractString, types::Set{String}) where {M}
    isempty(types) && return TreeSitter.Node[]
    return collect_tree(match, tree, profile, source)
end

"""
    is_identical_operands(node, profile, source) -> Bool

True when `node` is a binary expression (`profile.binary_expr_types`) whose two
operands are textually identical, like `x == x` or `a && a`. The duplication is almost
always a mistake: a comparison that is always true or false, a redundant boolean.
Operators where equal operands are ordinary (`profile`-independent: `+`, `*`, shifts,
`!=` for a NaN check) are left alone. The `:identical_operands` rule reports one
finding per match.
"""
function is_identical_operands(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    TreeSitter.node_type(node) in profile.binary_expr_types || return false
    kids = collect(TreeSitter.named_children(node))
    return length(kids) >= 2 &&
        normalized_text(first(kids), source) == normalized_text(last(kids), source) &&
        !any(c -> normalized_text(c, source) in IDEMPOTENT_OPS, TreeSitter.children(node))
end

# Body blocks belonging to one conditional: those directly under it and under its
# continuation clauses (else, elseif, case), but not those inside a nested
# conditional, loop, or function. Conservative by design: a chain a grammar nests
# rather than flattens (an `else if` parsed as an `if` inside an `else`) yields only
# the branches reachable without crossing a fresh construct.
function branch_blocks(node::TreeSitter.Node, profile::LanguageProfile)
    blocks = TreeSitter.Node[]
    collect_branch_blocks!(blocks, node, profile)
    return blocks
end

function collect_branch_blocks!(blocks, node::TreeSitter.Node, profile::LanguageProfile)
    for c in TreeSitter.children(node)
        t = TreeSitter.node_type(c)
        if t in profile.body_types
            push!(blocks, c)
        elseif is_function(c, profile) || t in profile.nesting_types
            continue
        else
            collect_branch_blocks!(blocks, c, profile)
        end
    end
    return blocks
end

"""
    is_duplicate_branches(node, profile, source) -> Bool

True when `node` is a conditional (`profile.conditional_types`) whose branches are all
textually identical: every arm of an `if`/`else` chain or `switch` runs the same code,
so the condition decides nothing. At least two arms must be present to compare. The
`:duplicate_branches` rule reports one finding per match.
"""
function is_duplicate_branches(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    TreeSitter.node_type(node) in profile.conditional_types || return false
    blocks = branch_blocks(node, profile)
    length(blocks) >= 2 || return false
    texts = [normalized_text(b, source) for b in blocks]
    return all(==(first(texts)), texts)
end

"""
    unreachable_statements(tree, profile) -> Vector{TreeSitter.Node}

Statements that follow an unconditional control-flow terminator
(`profile.terminal_types`: `return`, `break`, `throw`) in the same block, and so can
never run. One finding per block, anchored on the first dead statement.
"""
function unreachable_statements(tree::TreeSitter.Tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    isempty(profile.terminal_types) && return out
    for body in collect_typed(tree, profile, profile.body_types)
        terminated = false
        for c in TreeSitter.children(body)
            (TreeSitter.is_named(c) && !(TreeSitter.node_type(c) in profile.comment_types)) || continue
            t = TreeSitter.node_type(c)
            if terminated && !(t in profile.trivial_body_types)
                push!(out, c)
                break
            end
            t in profile.terminal_types && (terminated = true)
        end
    end
    return out
end

"""
    empty_bodies(tree, profile) -> Vector{TreeSitter.Node}

Function nodes with no body, or a body that does no real work.
"""
empty_bodies(tree::TreeSitter.Tree, profile::LanguageProfile) =
    [u.node for u in functions(tree, profile) if empty_body(u.node, profile)]

"""
    empty_catches(tree, profile) -> Vector{TreeSitter.Node}

Exception-handling clauses with an empty or absent body, which swallow errors.
"""
empty_catches(tree::TreeSitter.Tree, profile::LanguageProfile) =
    collect_tree(is_empty_catch, tree, profile, "")

is_empty_catch(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    TreeSitter.node_type(node) in profile.catch_types &&
    empty_block(first_child_of(node, profile.body_types), profile)

"""
    stub_markers(tree, profile, source) -> Vector{TreeSitter.Node}

Comment nodes carrying a stub marker (`TODO`, `FIXME`, `XXX`, `HACK`).
"""
stub_markers(tree::TreeSitter.Tree, profile::LanguageProfile, source::AbstractString) =
    collect_tree(is_stub_comment, tree, profile, source)

# Shares the `node-type check && condition` shape of is_empty_catch but no logic: a
# catch-emptiness test versus a stub-marker regex. The verbose typed signature
# dominates the structural hash, so the two read as a near-miss with nothing to extract.
# dendro-ignore: near_duplicate
is_stub_comment(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString) =
    TreeSitter.node_type(node) in profile.comment_types &&
    occursin(STUB_PATTERN, TreeSitter.slice(source, node))

"""
    returns_in_finally(tree, profile) -> Vector{TreeSitter.Node}

Return statements inside a finally/ensure clause (`profile.finally_types`), which
discard a pending exception or return value. Empty for a language with no finally
construct.
"""
function returns_in_finally(tree::TreeSitter.Tree, profile::LanguageProfile)
    (isempty(profile.finally_types) || isempty(profile.return_types)) && return TreeSitter.Node[]
    return collect_tree(is_return_in_finally, tree, profile, "")
end

# A return whose nearest enclosing finally/function ancestor is a finally. Walking up
# `parent`, a finally seen before any function means the return runs in that finally;
# a function seen first means the return belongs to a nested callable, excluded. This
# matches the old "stop at a nested callable" descent exactly.
function is_return_in_finally(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    TreeSitter.node_type(node) in profile.return_types || return false
    p = TreeSitter.parent(node)
    while !TreeSitter.is_null(p)
        t = TreeSitter.node_type(p)
        t in profile.finally_types && return true
        is_function(p, profile) && return false
        p = TreeSitter.parent(p)
    end
    return false
end

# True when a statement is, or directly wraps, a single call: a bare call, or a
# return/expression statement whose only named child is a call.
function single_call(stmt::TreeSitter.Node, profile::LanguageProfile)
    TreeSitter.node_type(stmt) in profile.call_types && return true
    kids = collect(TreeSitter.named_children(stmt))
    return length(kids) == 1 && TreeSitter.node_type(only(kids)) in profile.call_types
end

"""
    trivial_wrappers(tree, profile) -> Vector{TreeSitter.Node}

Function nodes whose body is one delegating call, an indirection that adds no
behaviour. Empty for a language with no call-expression concept.
"""
function trivial_wrappers(tree::TreeSitter.Tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    isempty(profile.call_types) && return out
    for u in functions(tree, profile)
        body = function_body(u.node, profile)
        body === nothing && continue
        if TreeSitter.node_type(body) in profile.body_types
            stmts = [
                c for c in TreeSitter.children(body)
                    if TreeSitter.is_named(c) && !(TreeSitter.node_type(c) in profile.trivial_body_types)
            ]
            length(stmts) == 1 && single_call(only(stmts), profile) && push!(out, u.node)
        else
            single_call(body, profile) && push!(out, u.node)
        end
    end
    return out
end
