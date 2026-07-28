# One parsed source file, carrying everything the baseline, the per-file scoring
# pass, and duplicate clustering need, so no file is parsed twice. Concrete in
# every field, so consumers that take a `Vector{ParsedFile}` dispatch statically
# instead of through `getproperty(::Any)`.

"""
    ParsedFile

One parsed file in the corpus: its `language`, the `profile` that language resolved
through, the raw `source`, the `file` path, the tree-sitter `tree`, the `index` of nodes
the language query identified, and the inline suppression `directives` found in it.

The `profile` is carried per file so the corpus passes that need a language's scopes or
linkage query can reach it, which a language registered from a config file cannot be
looked up for by name alone. `language` is the profile's own name, kept as a field
because it keys the baseline, the clone buckets, and the naturalness models; the
constructor derives it, so the two cannot disagree.
"""
struct ParsedFile
    language::Symbol
    profile::LanguageProfile
    source::String
    file::String
    tree::TreeSitter.Tree
    index::QueryIndex
    directives::Vector{Directive}
end

ParsedFile(
    profile::LanguageProfile, source::String, file::String,
    tree::TreeSitter.Tree, index::QueryIndex, directives::Vector{Directive}
) = ParsedFile(profile.name, profile, source, file, tree, index, directives)

# The scopes and linkage queries for a parsed file's own language, the form the corpus
# passes read: they hold a `ParsedFile` and no registry, so the profile travels with it.
scopes_query_for(f::ParsedFile) = scopes_query_for(f.profile)
imports_query_for(f::ParsedFile) = imports_query_for(f.profile)
