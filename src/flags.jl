# Flag metrics: presence is the finding, no distribution. These target failure
# modes common in generated code, swallowed errors and unfinished stubs.

const STUB_PATTERN = r"\b(?:TODO|FIXME|XXX|HACK)\b"i

# Operators where two equal operands are ordinary, not a mistake: doubling (`x + x`),
# scaling (`x * x`), shifts, the `x != x` NaN check, `x / x` NaN/identity construction
# (`0.0 / 0.0`), and `=>` pair construction, where an identity entry
# (`"Accept" => "Accept"`) is a canonicalisation table, not a redundant comparison.
const IDEMPOTENT_OPS = Set{String}(["+", "*", "**", "<<", ">>", "/", "!=", "!==", "=>"])

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

# True when `node`'s signature carries initialization that does a constructor's work:
# a PHP promoted parameter, a C++ member-initializer list. Stops at a nested callable
# so an inner constructor's init never counts for the outer unit.
function has_init(node::TreeSitter.Node, index::QueryIndex)
    isempty(index.init.ids) && return false
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        c in index.init && return true
        has_init(c, index) && return true
    end
    return false
end

"""
    empty_body(node, index) -> Bool

True when the function `node` has an empty body. For a brace-bodied language an empty
body is a present block that does no real work; a bodyless declaration (an interface or
abstract method, a C++ `= default`/`= delete`) is a contract, not flagged. For a
keyword-delimited language (Julia `function … end`, Ruby `def … end`) an absent block
is itself the empty body, except a bare `function f end`, a forward declaration of a
zero-method generic function whose signature is a name rather than a call, a contract
left unflagged like a brace-bodied declaration. A short-form `f(x) = expr` has an
expression body, which always does work. A constructor whose work is signature-level
initialization, a PHP promoted parameter or a C++ member-initializer list, is not empty
though its block is.
"""
function empty_body(node::TreeSitter.Node, index::QueryIndex)
    body = function_body(node, index)
    body === nothing && return node in index.requires_body
    body in index.body || return false
    empty_block(body, index) || return false
    return !has_init(node, index)
end

"""
    is_identical_operands(node, index) -> Bool

True when `node` is a binary expression whose two operands are textually identical,
like `x == x` or `a && a`. The duplication is almost always a mistake: a comparison
that is always true or false, a redundant boolean. Operators where equal operands
are ordinary (`+`, `*`, shifts, `/` and `!=` for NaN construction or a NaN check, `=>`
for an identity pair in a canonicalisation table) are left alone. A chained
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
    broad_catches(index) -> Vector{TreeSitter.Node}

Handlers broad enough to swallow interrupts and exits: a bare `except:`, `except
BaseException`, Java `catch (Throwable)`, C++ `catch (...)`, Ruby `rescue
Exception`, PHP `catch (Throwable)`. The query decides broadness, so a language
whose only catch form is untyped (JavaScript, Julia) reports nothing, and the
merely-wide tier (`except Exception`, `catch (Exception)`) is left alone.
"""
broad_catches(index::QueryIndex) = index.broad_catch.nodes

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

# The cross-language deliberate-unused convention: a name beginning with an
# underscore opts out of unused reporting. An empty slice (a name the grammar
# tokenizes away) has nothing to report either.
deliberately_unused(name::AbstractString) = isempty(name) || startswith(name, "_")

# Reference positions by name text, the use-test both unused flags share. A
# definition site or a signature's own parameter name is not a use.
function reference_positions(index::QueryIndex)
    caps = index.scope_captures
    uses = Dict{String, Vector{NodeId}}()
    for r in caps.refnodes
        rid = nodeid(r)
        (rid in caps.defids || hasid(index.parameter_name.ids, r)) && continue
        name = String(strip(TreeSitter.slice(index.source, r)))
        push!(get!(() -> NodeId[], uses, name), rid)
    end
    return uses
end

# Whether any reference named `name` lands inside the byte range `r`.
function used_within(uses::Dict{String, Vector{NodeId}}, name::AbstractString, r::Tuple{Int, Int})
    positions = get(uses, name, nothing)
    positions === nothing && return false
    return any(pos -> r[1] <= pos[1] && pos[2] <= r[2], positions)
end

"""
    unused_parameters(index) -> Vector{TreeSitter.Node}

Parameter names nothing in their function references. A same-named reference anywhere
in the unit counts as a use, including inside a nested callable, the conservative
reading. Underscore-prefixed names opt out. A bodyless declaration keeps its
parameters (they are its signature), and an empty or stub body is already the
`empty_body` finding, so its parameters are not additionally dead. Empty for a
language whose parameters carry no names (bash).
"""
function unused_parameters(index::QueryIndex)
    out = TreeSitter.Node[]
    isempty(index.parameter_name.nodes) && return out
    units = functions(index)
    ranges = unit_ranges(index)
    uses = reference_positions(index)
    for p in index.parameter_name.nodes
        pid = nodeid(p)
        ui = containing_unit(ranges, pid[1], pid[2])
        ui == 0 && continue
        node = units[ui].node
        (function_body(node, index) === nothing || empty_body(node, index)) && continue
        name = String(strip(TreeSitter.slice(index.source, p)))
        deliberately_unused(name) && continue
        used_within(uses, name, ranges[ui]) || push!(out, p)
    end
    return out
end

"""
    unused_locals(index) -> Vector{TreeSitter.Node}

Local bindings inside a function whose name nothing in that function references. The
use-test is by name over the whole unit, not by resolved binding: a language like
Julia rebinds an enclosing local from a nested scope (`best = i` inside a `for`),
which the scope model reads as a fresh definition, so binding-level reporting would
flag live variables. Rebindings of one name in one unit are one variable, reported
once at the first binding. Underscore-prefixed names opt out. A top-level binding is
visible across files and belongs to `unreferenced`, not here. Empty for a language
whose scopes query captures no local bindings (php).
"""
function unused_locals(index::QueryIndex)
    out = TreeSitter.Node[]
    caps = index.scope_captures
    isempty(caps.defnodes) && return out
    ranges = unit_ranges(index)
    uses = reference_positions(index)
    seen = Set{Tuple{Int, String}}()
    for (i, d) in enumerate(caps.defnodes)
        caps.defkinds[i] in LOCAL_KINDS || continue
        did = nodeid(d)
        ui = containing_unit(ranges, did[1], did[2])
        ui == 0 && continue
        name = String(strip(TreeSitter.slice(index.source, d)))
        deliberately_unused(name) && continue
        (ui, name) in seen && continue
        push!(seen, (ui, name))
        used_within(uses, name, ranges[ui]) || push!(out, d)
    end
    return out
end

"""
    local_count(unit, index) -> Int

Number of distinct local names bound within the function, from the scopes query's
local definitions: plain locals, loop bindings, and locals in nested soft scopes.
Rebindings of one name are one variable, a nested callable's bindings belong to it,
and underscore-prefixed names are discards, not locals. Zero for a language whose
scopes query captures no local bindings (php). A scalar rule, housed here beside
the unused flags because it reads the same binding substrate.
"""
function local_count(unit::FunctionUnit, index::QueryIndex)
    caps = index.scope_captures
    isempty(caps.defnodes) && return 0
    ranges = unit_ranges(index)
    span = TreeSitter.byte_range(unit.node)
    names = Set{String}()
    for (i, d) in enumerate(caps.defnodes)
        caps.defkinds[i] in LOCAL_KINDS || continue
        did = nodeid(d)
        ui = containing_unit(ranges, did[1], did[2])
        (ui != 0 && ranges[ui] == span) || continue
        name = String(strip(TreeSitter.slice(index.source, d)))
        deliberately_unused(name) && continue
        push!(names, name)
    end
    return length(names)
end

"""
    shadowed_variables(index) -> Vector{TreeSitter.Node}

Fresh local bindings whose name an enclosing scope already binds, hiding the outer
variable. Only a fresh-binding form (`:local` kind) can shadow: a Julia statement
assignment in a nested scope (`:assign`) rebinds the enclosing local instead, the
accumulator idiom, and never reports. Parameters are not scope definitions, so a
local hiding a parameter is not seen, and a scope's kind is not modelled, so a
method local matching a class attribute reports even where the language gives
methods no lexical view of it. Underscore-prefixed names opt out.
"""
function shadowed_variables(index::QueryIndex)
    out = TreeSitter.Node[]
    caps = index.scope_captures
    isempty(caps.defnodes) && return out
    for (i, d) in enumerate(caps.defnodes)
        caps.defkinds[i] === :local || continue
        did = nodeid(d)
        name = String(strip(TreeSitter.slice(index.source, d)))
        deliberately_unused(name) && continue
        owner = owning_scope(caps.scopes, did[1], did[2], false)
        owner === nothing && continue
        # Rebinding within one scope is one variable; only its winner can shadow.
        winner = get(owner.defs, name, nothing)
        (winner === nothing || nodeid(winner) != did) && continue
        for s in caps.scopes
            (s.from <= owner.from && owner.to <= s.to) || continue
            (s.to - s.from) > (owner.to - owner.from) || continue
            haskey(s.defs, name) || continue
            push!(out, d)
            break
        end
    end
    return out
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
