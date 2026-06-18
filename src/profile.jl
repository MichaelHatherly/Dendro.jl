# Per-language configuration. A profile names a language Dendro can analyse; the
# node types it measures live in its tree-sitter query (`src/queries/<name>.scm`),
# resolved through [`query_for`](@ref) and collected into a [`QueryIndex`](@ref).

"""
    LanguageProfile

Names a language Dendro recognises. The constructs it measures are defined by the
language's query, not by this type.
"""
struct LanguageProfile
    name::Symbol
end
