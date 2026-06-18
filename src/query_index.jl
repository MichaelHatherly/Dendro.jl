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

# Stable identity of a node within one tree: its byte span and grammar symbol. A
# node has no exposed id and is not hashable, so this stands in as a `Set` key.
const NodeId = Tuple{Int, Int, UInt16}
nodeid(n::TreeSitter.Node) = (TreeSitter.byte_range(n)..., TreeSitter.node_symbol(n))

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

    QueryIndex(language::Symbol, source::String) = new(
        language, source, FunctionUnit[], Set{NodeId}(),
        Concept(), Concept(), Concept(), Concept(), Concept(), Concept(),
        Concept(), Concept(), Concept(), Concept(), Concept(), Concept(),
        Concept(), Concept(), Concept(), Concept(), Concept(), Concept(),
    )
end

# Route one capture to its concept. A plain if/elseif so the dispatch stays
# concretely typed: every branch pushes into a `Concept` field. A name with no
# branch is a query bug, not a silent drop: the `else` throws, and the suite guards
# every query's captures against `CONCEPT_NAMES`.
function dispatch!(idx::QueryIndex, name::AbstractString, n::TreeSitter.Node)
    if name == "short_function"
        record!(idx.short_function, n)
    elseif name == "decision"
        record!(idx.decision, n)
    elseif name == "continuation"
        record!(idx.continuation, n)
    elseif name == "nesting"
        record!(idx.nesting, n)
    elseif name == "short_circuit"
        record!(idx.short_circuit, n)
    elseif name == "parameter"
        record!(idx.parameter, n)
    elseif name == "body"
        record!(idx.body, n)
    elseif name == "catch"
        record!(idx.catch_clause, n)
    elseif name == "comment"
        record!(idx.comment, n)
    elseif name == "name"
        record!(idx.name, n)
    elseif name == "trivial_body"
        record!(idx.trivial_body, n)
    elseif name == "return"
        record!(idx.return_stmt, n)
    elseif name == "finally"
        record!(idx.finally_clause, n)
    elseif name == "call"
        record!(idx.call, n)
    elseif name == "binary_expr"
        record!(idx.binary_expr, n)
    elseif name == "conditional"
        record!(idx.conditional, n)
    elseif name == "terminal"
        record!(idx.terminal, n)
    elseif name == "operator"
        record!(idx.operator, n)
    else
        throw(ArgumentError("unknown capture name :$name"))
    end
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
    build_index(tree, language, source, query) -> QueryIndex

Run `query` over `tree` once and collect every capture into a [`QueryIndex`](@ref).
`@function` captures become [`FunctionUnit`](@ref)s; every other capture is filed
under its concept.
"""
function build_index(tree::TreeSitter.Tree, language::Symbol, source::AbstractString, query::TreeSitter.Query)
    idx = QueryIndex(language, String(source))
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
