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

"""
    empty_body(node, profile) -> Bool

True when the function `node` has no body, or a body that does no real work.
"""
empty_body(node::TreeSitter.Node, profile::LanguageProfile) =
    empty_block(first_child_of(node, profile.body_types), profile)

"""
    identical_operands(tree, profile, source) -> Vector{TreeSitter.Node}

Binary expressions (`profile.binary_expr_types`) whose two operands are textually
identical, like `x == x` or `a && a`. The duplication is almost always a mistake:
a comparison that is always true or false, a redundant boolean. Operators where
equal operands are ordinary (`profile`-independent: `+`, `*`, shifts, `!=` for a
NaN check) are left alone.
"""
function identical_operands(tree, profile::LanguageProfile, source::AbstractString)
    out = TreeSitter.Node[]
    isempty(profile.binary_expr_types) && return out
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.binary_expr_types
            kids = collect(TreeSitter.named_children(n))
            if length(kids) >= 2 &&
               normalized_text(first(kids), source) == normalized_text(last(kids), source) &&
               !any(c -> normalized_text(c, source) in IDEMPOTENT_OPS, TreeSitter.children(n))
                push!(out, n)
            end
        end
        nothing
    end
    return out
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
        elseif t in profile.function_types || t in profile.nesting_types
            continue
        else
            collect_branch_blocks!(blocks, c, profile)
        end
    end
    return blocks
end

"""
    duplicate_branches(tree, profile, source) -> Vector{TreeSitter.Node}

Conditionals (`profile.conditional_types`) whose branches are all textually
identical: every arm of an `if`/`else` chain or `switch` runs the same code, so the
condition decides nothing. At least two arms must be present to compare.
"""
function duplicate_branches(tree, profile::LanguageProfile, source::AbstractString)
    out = TreeSitter.Node[]
    isempty(profile.conditional_types) && return out
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.conditional_types
            blocks = branch_blocks(n, profile)
            if length(blocks) >= 2
                texts = [normalized_text(b, source) for b in blocks]
                all(==(first(texts)), texts) && push!(out, n)
            end
        end
        nothing
    end
    return out
end

"""
    unreachable_statements(tree, profile) -> Vector{TreeSitter.Node}

Statements that follow an unconditional control-flow terminator
(`profile.terminal_types`: `return`, `break`, `throw`) in the same block, and so can
never run. One finding per block, anchored on the first dead statement.
"""
function unreachable_statements(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    isempty(profile.terminal_types) && return out
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.body_types
            terminated = false
            for c in TreeSitter.children(n)
                (TreeSitter.is_named(c) && !(TreeSitter.node_type(c) in profile.comment_types)) || continue
                t = TreeSitter.node_type(c)
                if terminated && !(t in profile.trivial_body_types)
                    push!(out, c)
                    break
                end
                t in profile.terminal_types && (terminated = true)
            end
        end
        nothing
    end
    return out
end

"""
    empty_bodies(tree, profile) -> Vector{TreeSitter.Node}

Function nodes with no body, or a body that does no real work.
"""
empty_bodies(tree, profile::LanguageProfile) =
    [u.node for u in functions(tree, profile) if empty_body(u.node, profile)]

"""
    empty_catches(tree, profile) -> Vector{TreeSitter.Node}

Exception-handling clauses with an empty or absent body, which swallow errors.
"""
function empty_catches(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.catch_types
            empty_block(first_child_of(n, profile.body_types), profile) && push!(out, n)
        end
        nothing
    end
    return out
end

"""
    stub_markers(tree, profile, source) -> Vector{TreeSitter.Node}

Comment nodes carrying a stub marker (`TODO`, `FIXME`, `XXX`, `HACK`).
"""
function stub_markers(tree, profile::LanguageProfile, source::AbstractString)
    out = TreeSitter.Node[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.comment_types
            occursin(STUB_PATTERN, TreeSitter.slice(source, n)) && push!(out, n)
        end
        nothing
    end
    return out
end

"""
    returns_in_finally(tree, profile) -> Vector{TreeSitter.Node}

Return statements inside a finally/ensure clause (`profile.finally_types`), which
discard a pending exception or return value. Empty for a language with no finally
construct.
"""
function returns_in_finally(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    (isempty(profile.finally_types) || isempty(profile.return_types)) && return out
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.finally_types
            traverse_unit(n, profile) do m, e
                e && TreeSitter.node_type(m) in profile.return_types && push!(out, m)
                nothing
            end
        end
        nothing
    end
    return out
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
function trivial_wrappers(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    isempty(profile.call_types) && return out
    for u in functions(tree, profile)
        body = first_child_of(u.node, profile.body_types)
        body === nothing && continue
        stmts = [c for c in TreeSitter.children(body)
                 if TreeSitter.is_named(c) && !(TreeSitter.node_type(c) in profile.trivial_body_types)]
        length(stmts) == 1 && single_call(only(stmts), profile) && push!(out, u.node)
    end
    return out
end
