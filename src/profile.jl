# Per-language configuration. A profile names a language Dendro can analyse and says
# where its grammar and queries come from; the node types it measures live in its
# tree-sitter query (`<queries>/<name>.scm`), resolved through [`query_for`](@ref) and
# collected into a [`QueryIndex`](@ref).

# The built-in query source directory, made relocatable so the `.scm` files resolve
# after precompilation or when the package is moved.
const QUERIES_DIR = RelocatableFolders.@path joinpath(@__DIR__, "queries")

"""
    LanguageProfile(name, grammar, queries, extensions = String[])
    LanguageProfile(name)

Names a language Dendro recognises and where to load it from. `grammar` is either a
directory holding a tree-sitter grammar repository or a language name resolved to its
`tree_sitter_<name>_jll` package. `queries` is the directory holding `<name>.scm` and
its optional `.scopes.scm` and `.imports.scm` companions. `extensions` are the file
extensions the language claims, without a leading dot.

The one-argument form builds a profile for a language Dendro ships: the grammar is the
JLL named after it and the queries are the package's own. Such a profile carries an
empty `queries`, since the built-in directory has to be resolved at read time through
[`queries_dir`](@ref) to survive the package being moved after precompilation, and
empty `extensions`, since [`EXTENSIONS`](@ref) is the one table naming those.

The constructs a language measures are defined by its query, not by this type.
"""
struct LanguageProfile
    name::Symbol
    grammar::String
    queries::String
    extensions::Vector{String}
end

LanguageProfile(name::Symbol, grammar::AbstractString, queries::AbstractString) =
    LanguageProfile(name, grammar, queries, String[])
LanguageProfile(name::Symbol) = LanguageProfile(name, String(name), "")

# Profiles key the query caches, so two projects that register the same language name
# against different grammars or queries never share a compiled query. The default
# `===` would compare the `String` fields by identity and miss two equal profiles
# built from separately parsed config files. Extensions are excluded: they select which
# files a language reads, not how its source is parsed and measured.
Base.:(==)(a::LanguageProfile, b::LanguageProfile) =
    a.name === b.name && a.grammar == b.grammar && a.queries == b.queries
Base.hash(p::LanguageProfile, h::UInt) = hash(p.queries, hash(p.grammar, hash(p.name, h)))

"""
    queries_dir(profile) -> String

The directory holding `profile`'s query files. A profile registered from a config file
names its own; one Dendro ships resolves the package's `src/queries` at read time, so a
precompiled package that has since moved still finds its queries.
"""
queries_dir(p::LanguageProfile)::String = isempty(p.queries) ? String(QUERIES_DIR) : p.queries
