# Per-language configuration mapping abstract metric concepts to concrete
# tree-sitter node types. Profiles are pure data and carry no parser reference.

"""
    LanguageProfile

Names the tree-sitter node types a language uses for the constructs Dendro
measures.

- `function_types`: nodes that define a callable unit.
- `decision_types`: branch points counted for cyclomatic complexity.
- `short_circuit_ops`: operator texts (`"&&"`, `"||"`) that add a branch.
- `nesting_types`: control constructs that introduce a level of nesting.
- `parameter_types`: the node that holds a function's parameter list.
- `body_types`: the block node that holds a function or clause body.
- `catch_types`: exception-handling clauses, checked for swallowed errors.
- `comment_types`: comment nodes, scanned for stub markers.
- `name_types`: identifier node used to label a function in reports.
- `trivial_body_types`: statements that count as no real work (e.g. `pass`), so
  a body holding only these reads as empty.
- `return_types`: return-statement nodes, counted per function and checked inside
  finally clauses.
- `finally_types`: finally/ensure clauses, checked for returns that discard errors.
- `call_types`: call-expression nodes, used to spot a function that only delegates.
- `binary_expr_types`: binary-expression nodes, checked for identical operands.
- `conditional_types`: branching roots (`if`, `switch`), checked for arms that are
  all identical.
- `terminal_types`: statements that end control flow (`return`, `break`, `throw`),
  after which more code in the same block is unreachable.
"""
struct LanguageProfile
    name::Symbol
    function_types::Set{String}
    decision_types::Set{String}
    short_circuit_ops::Set{String}
    nesting_types::Set{String}
    parameter_types::Set{String}
    body_types::Set{String}
    catch_types::Set{String}
    comment_types::Set{String}
    name_types::Set{String}
    trivial_body_types::Set{String}
    return_types::Set{String}
    finally_types::Set{String}
    call_types::Set{String}
    binary_expr_types::Set{String}
    conditional_types::Set{String}
    terminal_types::Set{String}
end

# Keyword constructor. Sets that a language does not use default to empty, so
# each profile lists only the node types it actually has.
function LanguageProfile(
    name::Symbol;
    function_types,
    decision_types,
    body_types,
    name_types,
    short_circuit_ops = String[],
    nesting_types = String[],
    parameter_types = String[],
    catch_types = String[],
    comment_types = String[],
    trivial_body_types = String[],
    return_types = String[],
    finally_types = String[],
    call_types = String[],
    binary_expr_types = String[],
    conditional_types = String[],
    terminal_types = String[],
)
    return LanguageProfile(
        name,
        Set{String}(function_types),
        Set{String}(decision_types),
        Set{String}(short_circuit_ops),
        Set{String}(nesting_types),
        Set{String}(parameter_types),
        Set{String}(body_types),
        Set{String}(catch_types),
        Set{String}(comment_types),
        Set{String}(name_types),
        Set{String}(trivial_body_types),
        Set{String}(return_types),
        Set{String}(finally_types),
        Set{String}(call_types),
        Set{String}(binary_expr_types),
        Set{String}(conditional_types),
        Set{String}(terminal_types),
    )
end
