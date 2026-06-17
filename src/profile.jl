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
"""
struct LanguageProfile
    name::Symbol
    function_types::Set{String}
    decision_types::Set{String}
    short_circuit_ops::Set{String}
    nesting_types::Set{String}
    parameter_types::Set{String}
end
