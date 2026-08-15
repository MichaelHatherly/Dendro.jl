# Language identification and lazy grammar resolution. A [`LanguageProfile`](@ref) says
# where a language's grammar and queries come from; everything here resolves one into
# the parser and compiled queries a scan reads, caching per profile so a language that
# two projects define differently never shares a compiled query.

# Stable identity of a node within one tree: its byte span and grammar symbol. A
# node has no exposed id and is not hashable, so this stands in as a `Set` key. Lives
# early, so every later file can key nodes by identity.
const NodeId = Tuple{Int, Int, UInt16}
nodeid(n::TreeSitter.Node) = (TreeSitter.byte_range(n)..., TreeSitter.node_symbol(n))

# File extension to language name for the languages Dendro ships. A profile registered
# from a config file carries its own extensions, so `language_for_path` reads a registry
# rather than this table alone.
const EXTENSIONS = Dict{String, Symbol}(
    "jl" => :julia,
    "py" => :python,
    "sh" => :bash,
    "bash" => :bash,
    "zsh" => :bash,
    "c" => :c,
    "h" => :c,
    "cpp" => :cpp,
    "cc" => :cpp,
    "cxx" => :cpp,
    "hpp" => :cpp,
    "hh" => :cpp,
    "hxx" => :cpp,
    "go" => :go,
    "java" => :java,
    "js" => :javascript,
    "mjs" => :javascript,
    "cjs" => :javascript,
    "jsx" => :javascript,
    "php" => :php,
    "rb" => :ruby,
    "rs" => :rust,
    "ts" => :typescript,
    "tsx" => :typescript,
)

"""
    extension_map(profiles) -> Dict{String, Symbol}

The extension-to-language table a registry resolves file paths through: the built-in
[`EXTENSIONS`](@ref) for the languages `profiles` carries, plus the extensions each
profile claims for itself, which win on a clash so a project can redirect an extension
to its own language. Built once per scan and passed to [`language_for_path`](@ref),
which a directory walk calls per file.
"""
function extension_map(profiles::Dict{Symbol, LanguageProfile})
    exts = Dict{String, Symbol}()
    for (ext, lang) in EXTENSIONS
        haskey(profiles, lang) && (exts[ext] = lang)
    end
    for (lang, profile) in profiles
        for ext in profile.extensions
            exts[ext] = lang
        end
    end
    return exts
end

"""
    language_for_path(path, extensions = EXTENSIONS) -> Union{Symbol,Nothing}

Return the language name for a file path, or `nothing` when its extension is
unrecognised. `extensions` is an [`extension_map`](@ref) of the scan's registry, so a
language registered in a `.dendro.toml` claims its own file types; it defaults to the
built-in table, the languages Dendro ships.
"""
function language_for_path(path::AbstractString, extensions::Dict{String, Symbol} = EXTENSIONS)
    ext = lstrip(lowercase(last(splitext(path))), '.')
    return get(extensions, ext, nothing)
end

"""
    profile_for(name::Symbol) -> LanguageProfile

The profile a bare language name resolves to: the one Dendro ships for `name`, or, for a
name it does not, a profile reading the JLL and queries named after it. The by-name entry
to [`parser_for`](@ref) and the query accessors, for a caller holding no registry; a scan
passes its own resolved profiles instead.
"""
profile_for(name::Symbol) = get(PROFILES, name, LanguageProfile(name))

"""
    language_module(name::Symbol) -> Module

Lazy-load the `tree_sitter_<name>_jll` package for `name`, erroring with an
install hint when it is not present in the active environment.
"""
function language_module(name::Symbol)
    pkgname = "tree_sitter_$(name)_jll"
    id = Base.identify_package(pkgname)
    id === nothing && error(
        "Dendro: no parser for language :$name. Add it with " *
            "`import Pkg; Pkg.add(\"$pkgname\")`.",
    )
    return lock(() -> Base.require(id), CACHE_LOCK)
end

# Grammars cached per profile. A `TreeSitter.Language` wraps a C pointer that cannot
# survive precompilation, so it is loaded on first use like the compiled queries.
const GRAMMAR_CACHE = Dict{LanguageProfile, TreeSitter.Language}()

"""
    language_grammar(profile) -> TreeSitter.Language

The loaded tree-sitter grammar for `profile`, cached. A `grammar` naming a directory is
read as a local grammar repository, which needs a `tree-sitter.json` and a built shared
library beside it; anything else names the `tree_sitter_<grammar>_jll` package to load.
"""
function language_grammar(profile::LanguageProfile)::TreeSitter.Language
    return lock(CACHE_LOCK) do
        get!(GRAMMAR_CACHE, profile) do
            isdir(profile.grammar) && return TreeSitter.Language(profile.grammar)
            return TreeSitter.Language(language_module(Symbol(profile.grammar)))
        end
    end
end

"""
    parser_for(profile) -> TreeSitter.Parser
    parser_for(language) -> TreeSitter.Parser

Build a parser for `profile`, or for a language Dendro ships given by name (`:julia`,
`"julia"`). Grammars load lazily, so Dendro carries no parser dependencies of its own.
"""
parser_for(profile::LanguageProfile) = TreeSitter.Parser(language_grammar(profile))
parser_for(name::Symbol) = parser_for(profile_for(name))
parser_for(name::AbstractString) = parser_for(Symbol(lowercase(name)))

"""
    parse_source(parser, source) -> TreeSitter.Tree

Parse `source` into the tree every Dendro pass reads.

Declines injection resolution. A grammar's injections query finds the regions where
another language is embedded, a docstring, a comment, a regex literal, and parses each
into a layer of its own. Dendro reads one language per file: its queries run against the
root layer and nothing downstream reaches for a tree's `children` or `unresolved`, so
resolving those regions is work no pass can see.
"""
parse_source(parser::TreeSitter.Parser, source::AbstractString) =
    TreeSitter.parse(parser, source; injections = false)

# Guards the grammar load and the lazy query caches against concurrent first-touch: `get!`
# on a plain Dict corrupts it under a concurrent resize. Reentrant, since a cache fill
# loads the grammar inside the lock; uncontended once a language is warm.
const CACHE_LOCK = ReentrantLock()

# Compiled queries cached per profile. Populated lazily at runtime: a `Query` wraps
# a C pointer that cannot survive precompilation, so it is built on first use.
const QUERY_CACHE = Dict{LanguageProfile, TreeSitter.Query}()

"""
    query_for(profile) -> TreeSitter.Query
    query_for(language) -> TreeSitter.Query

The compiled node-identification query for `profile`, read from `<queries>/<name>.scm`
and cached. The grammar loads lazily, so the query compiles on first use against the
freshly loaded grammar. A language Dendro ships can be named directly.
"""
function query_for(profile::LanguageProfile)
    return lock(CACHE_LOCK) do
        get!(QUERY_CACHE, profile) do
            source = read(joinpath(queries_dir(profile), "$(profile.name).scm"), String)
            TreeSitter.Query(language_grammar(profile), source)
        end
    end
end

query_for(name::Symbol) = query_for(profile_for(name))

# Compiled scopes queries cached per profile, `nothing` for a language that ships
# none. Cached like `query_for`, so the missing-file check runs once.
const SCOPES_QUERY_CACHE = Dict{LanguageProfile, Union{TreeSitter.Query, Nothing}}()

"""
    scopes_query_for(profile) -> Union{TreeSitter.Query, Nothing}

The compiled lexical-scopes query for `profile`, read from `<queries>/<name>.scopes.scm`,
or `nothing` when the language ships none. A language without a scopes query carries no
bindings, and the cohesion metric skips it rather than treating every function as isolated.
"""
function scopes_query_for(profile::LanguageProfile)::Union{TreeSitter.Query, Nothing}
    return lock(CACHE_LOCK) do
        get!(SCOPES_QUERY_CACHE, profile) do
            path = joinpath(queries_dir(profile), "$(profile.name).scopes.scm")
            isfile(path) || return nothing
            TreeSitter.Query(language_grammar(profile), read(path, String))
        end
    end
end

scopes_query_for(name::Symbol) = scopes_query_for(profile_for(name))

# Compiled linkage queries cached per profile, `nothing` for a language that ships
# none. Same lazy, cache-once shape as `scopes_query_for`.
const IMPORTS_QUERY_CACHE = Dict{LanguageProfile, Union{TreeSitter.Query, Nothing}}()

"""
    imports_query_for(profile) -> Union{TreeSitter.Query, Nothing}

The compiled linkage query for `profile`, read from `<queries>/<name>.imports.scm`, or
`nothing` when the language ships none. It tags namespace regions (`@module`), import
and export statements, and `include`/`require` path strings, the captures the corpus
binding graph reads to resolve a reference across files.
"""
# Same lazy load and cache as `scopes_query_for`, differing only in the file kind, so
# the two share a shape with nothing left to extract.
# dendro-ignore: duplicate
function imports_query_for(profile::LanguageProfile)::Union{TreeSitter.Query, Nothing}
    return lock(CACHE_LOCK) do
        get!(IMPORTS_QUERY_CACHE, profile) do
            path = joinpath(queries_dir(profile), "$(profile.name).imports.scm")
            isfile(path) || return nothing
            TreeSitter.Query(language_grammar(profile), read(path, String))
        end
    end
end

imports_query_for(name::Symbol) = imports_query_for(profile_for(name))

# Populate every lazy per-profile cache before the corpus fan-outs, so no parallel task
# pays a grammar load or a query compile behind `CACHE_LOCK` mid fan-out; this also
# leaves the imports query warm for the linkage passes.
function warm_languages(profiles)
    for profile in profiles
        parser_for(profile)
        query_for(profile)
        scopes_query_for(profile)
        imports_query_for(profile)
    end
    return nothing
end
