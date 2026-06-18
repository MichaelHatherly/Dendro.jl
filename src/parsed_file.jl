# One parsed source file, carrying everything the baseline, the per-file scoring
# pass, and duplicate clustering need, so no file is parsed twice. Concrete in
# every field, so consumers that take a `Vector{ParsedFile}` dispatch statically
# instead of through `getproperty(::Any)`.

"""
    ParsedFile

One parsed file in the corpus: its `language`, the resolved `profile`, the raw
`source`, the `file` path, the tree-sitter `tree`, and the inline suppression
`directives` found in it.
"""
struct ParsedFile
    language::Symbol
    profile::LanguageProfile
    source::String
    file::String
    tree::TreeSitter.Tree
    directives::Vector{Directive}
end
