# Query-driven node identification. A language's `.scm` query tags every construct
# Dendro measures with a capture naming the concept. Running it once over a tree
# yields a QueryIndex: the function units, plus per concept the matched nodes and a
# set of their identities for membership tests during scoring. Identification moves
# out of imperative node-type checks into the query; metric code only asks whether a
# node was tagged.

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

# Nodes captured for one concept: the nodes in capture order, and their ids for
# O(1) membership. Both are filled together as the query's captures are walked.
struct Concept
    nodes::Vector{TreeSitter.Node}
    ids::Set{NodeId}
end
Concept() = Concept(TreeSitter.Node[], Set{NodeId}())

# True when `n`'s identity is one of `ids`, the membership test underlying both
# concept lookups and the function-unit boundary.
hasid(ids::Set{NodeId}, n::TreeSitter.Node) = nodeid(n) in ids

# `node in concept` tests whether the query tagged `node` for that concept.
Base.in(n::TreeSitter.Node, c::Concept) = hasid(c.ids, n)

# Record a captured node in a concept: keep it in order and index its identity.
function record!(c::Concept, n::TreeSitter.Node)
    push!(c.nodes, n)
    push!(c.ids, nodeid(n))
    return c
end

# The capture names a query may use, the contract between a `.scm` and this index.
# A capture outside this set has no field to record into; `dispatch!` throws on one,
# and the suite guards every query's captures against this set. The reserved-word
# concepts (`catch`, `return`, `finally`) map to the `_clause`/`_stmt` fields below.
const CONCEPT_NAMES = (
    :short_function, :decision, :continuation, :nesting, :short_circuit,
    :parameter, :body, :catch, :comment, :name, :trivial_body, :return,
    :finally, :call, :binary_expr, :conditional, :terminal, :operator,
    :loop, :switch, :ternary, :try, :case, :def_name, :init, :requires_body,
)

"""
    QueryIndex(language, source)

One tree's identified nodes. `functions` are the callable units and `function_ids`
their identities (the no-descend boundary for unit-scoped metrics); every other
field is the [`Concept`](@ref) for one measured construct. `source` is the file
text, carried so scoring can slice node text without a separate argument. The
constructor builds an empty index; `build_index` fills the concepts by name through
[`dispatch!`](@ref) as it walks the query's captures, so initialisation lives beside
the field declarations rather than at the call site.
"""
struct QueryIndex
    language::Symbol
    source::String
    functions::Vector{FunctionUnit}
    function_ids::Set{NodeId}
    short_function::Concept
    decision::Concept
    continuation::Concept
    nesting::Concept
    short_circuit::Concept
    parameter::Concept
    body::Concept
    catch_clause::Concept
    comment::Concept
    name::Concept
    trivial_body::Concept
    return_stmt::Concept
    finally_clause::Concept
    call::Concept
    binary_expr::Concept
    conditional::Concept
    terminal::Concept
    operator::Concept
    loop::Concept
    switch::Concept
    ternary::Concept
    try_stmt::Concept
    case::Concept
    # The defining name of a callable, captured only where the lexical first name
    # would mislabel it: a qualified method `Module.method` whose final component is
    # the name. Empty for languages and definitions whose name is the first `@name`.
    def_name::Concept
    # Signature-level initialization that does a constructor's work with an empty body:
    # a PHP promoted parameter, a C++ member-initializer list. A unit carrying one is
    # not an empty body. Empty for languages with no such construct.
    init::Concept
    # A callable whose body is delimited by the construct itself (Julia `function … end`,
    # Ruby `def … end`), so an absent block is an empty implementation, not a declaration.
    # A brace-bodied language leaves this empty: there, an absent block is a contract.
    requires_body::Concept
    # Capture name to its concept, the same `Concept` objects the fields hold, so
    # `dispatch!` routes by name without a branch per concept. The reserved-word
    # captures (`catch`, `return`, `finally`, `try`) key to the `_clause`/`_stmt`
    # fields.
    by_name::Dict{String, Concept}
    # Each reference identifier's identity mapped to the in-file definition it
    # resolves to, filled by `resolve_bindings!` when a scopes query is supplied.
    bindings::Dict{NodeId, NodeId}
    # The lexical scope captures, walked once when a scopes query is supplied and
    # shared by the binding resolver, the corpus symbol table, and unbound-reference
    # collection, so the capture walk runs once per file. Empty for a file with no
    # scopes query or no scope regions.
    scope_captures::ScopeCaptures

    function QueryIndex(language::Symbol, source::String, scope_captures::ScopeCaptures = ScopeCaptures())
        short_function, decision, continuation, nesting = Concept(), Concept(), Concept(), Concept()
        short_circuit, parameter, body, catch_clause = Concept(), Concept(), Concept(), Concept()
        comment, name, trivial_body, return_stmt = Concept(), Concept(), Concept(), Concept()
        finally_clause, call, binary_expr, conditional = Concept(), Concept(), Concept(), Concept()
        terminal, operator, loop, switch = Concept(), Concept(), Concept(), Concept()
        ternary, try_stmt, case = Concept(), Concept(), Concept()
        def_name, init, requires_body = Concept(), Concept(), Concept()
        by_name = Dict{String, Concept}(
            "short_function" => short_function, "decision" => decision,
            "continuation" => continuation, "nesting" => nesting,
            "short_circuit" => short_circuit, "parameter" => parameter,
            "body" => body, "catch" => catch_clause, "comment" => comment,
            "name" => name, "trivial_body" => trivial_body, "return" => return_stmt,
            "finally" => finally_clause, "call" => call, "binary_expr" => binary_expr,
            "conditional" => conditional, "terminal" => terminal, "operator" => operator,
            "loop" => loop, "switch" => switch, "ternary" => ternary, "try" => try_stmt,
            "case" => case, "def_name" => def_name, "init" => init,
            "requires_body" => requires_body,
        )
        return new(
            language, source, FunctionUnit[], Set{NodeId}(),
            short_function, decision, continuation, nesting, short_circuit, parameter,
            body, catch_clause, comment, name, trivial_body, return_stmt, finally_clause,
            call, binary_expr, conditional, terminal, operator, loop, switch, ternary,
            try_stmt, case, def_name, init, requires_body, by_name, Dict{NodeId, NodeId}(), scope_captures,
        )
    end
end

# Route one capture to its concept by name. A name with no concept is a query bug,
# not a silent drop: the lookup misses and throws, and the suite guards every query's
# captures against `CONCEPT_NAMES`.
function dispatch!(idx::QueryIndex, name::AbstractString, n::TreeSitter.Node)
    c = get(idx.by_name, name, nothing)
    c === nothing && throw(ArgumentError("unknown capture name :$name"))
    record!(c, n)
    return nothing
end

# Pre-order rank of a node: earlier start first, larger span first on a tie, so an
# enclosing function sorts before one nested at the same offset. Matches the
# depth-first order a full tree walk produced.
function preorder_key(n::TreeSitter.Node)
    from, to = TreeSitter.byte_range(n)
    return (from, -to)
end

"""
    build_index(tree, language, source, query, scopes_query = nothing) -> QueryIndex

Run `query` over `tree` once and collect every capture into a [`QueryIndex`](@ref).
`@function` captures become [`FunctionUnit`](@ref)s; every other capture is filed
under its concept. When `scopes_query` is given, a second pass resolves each
reference to its in-file definition into `index.bindings`.
"""
function build_index(
        tree::TreeSitter.Tree, language::Symbol, source::String, query::TreeSitter.Query,
        scopes_query::Union{TreeSitter.Query, Nothing} = nothing
    )
    caps = ScopeCaptures()
    if scopes_query !== nothing
        c = collect_scopes(tree, scopes_query, source)
        if !isempty(c.scopes)
            assign_defs!(c, source)
            caps = c
        end
    end
    idx = QueryIndex(language, source, caps)
    funcs = TreeSitter.Node[]
    for cap in TreeSitter.each_capture(tree, query, source)
        name = TreeSitter.capture_name(query, cap)
        if name == "function"
            push_function!(funcs, idx.function_ids, cap.node)
        else
            dispatch!(idx, name, cap.node)
        end
    end
    sort!(funcs; by = preorder_key)
    for n in funcs
        sp = TreeSitter.start_point(n)
        ep = TreeSitter.end_point(n)
        Base.push!(idx.functions, FunctionUnit(n, Int(sp.row) + 1, Int(ep.row) + 1))
    end
    isempty(caps.scopes) || resolve_bindings!(idx.bindings, caps, source)
    return idx
end

# Record one function node once. Several patterns can tag the same definition (a
# `function ... end` matches one, a short form another), so dedupe on identity.
function push_function!(funcs::Vector{TreeSitter.Node}, ids::Set{NodeId}, n::TreeSitter.Node)
    id = nodeid(n)
    id in ids && return nothing
    Base.push!(ids, id)
    Base.push!(funcs, n)
    return nothing
end
