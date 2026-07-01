# Language identification and lazy parser resolution.

# Stable identity of a node within one tree: its byte span and grammar symbol. A
# node has no exposed id and is not hashable, so this stands in as a `Set` key. Lives
# here, the first include, so every later file can key nodes by identity.
const NodeId = Tuple{Int, Int, UInt16}
nodeid(n::TreeSitter.Node) = (TreeSitter.byte_range(n)..., TreeSitter.node_symbol(n))

# File extension to language name. Languages match TreeSitter.jl's supported set.
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
    language_for_path(path) -> Union{Symbol,Nothing}

Return the language name for a file path based on its extension, or `nothing`
when the extension is unrecognised.
"""
function language_for_path(path::AbstractString)
    ext = lstrip(lowercase(last(splitext(path))), '.')
    return get(EXTENSIONS, ext, nothing)
end

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

"""
    parser_for(language) -> TreeSitter.Parser

Build a parser for `language`, given as a language name (`:julia`, `"julia"`)
or a `tree_sitter_<lang>_jll` module. Language JLLs load lazily, so Dendro
carries no parser dependencies of its own.
"""
parser_for(name::Symbol) = TreeSitter.Parser(language_module(name))
parser_for(name::AbstractString) = parser_for(Symbol(lowercase(name)))
parser_for(mod::Module) = TreeSitter.Parser(mod)

# The query source directory, made relocatable so the `.scm` files resolve after
# precompilation or when the package is moved.
const QUERIES_DIR = RelocatableFolders.@path joinpath(@__DIR__, "queries")

# Guards the JLL load and the lazy query caches against concurrent first-touch: `get!` on a
# plain Dict corrupts it under a concurrent resize. Reentrant, since a cache fill loads the
# language module inside the lock; uncontended once a language is warm.
const CACHE_LOCK = ReentrantLock()

# Compiled queries cached per language. Populated lazily at runtime: a `Query` wraps
# a C pointer that cannot survive precompilation, so it is built on first use.
const QUERY_CACHE = Dict{Symbol, TreeSitter.Query}()

"""
    query_for(language) -> TreeSitter.Query

The compiled node-identification query for `language`, read from
`src/queries/<language>.scm` and cached. The language JLL loads lazily, so the
query compiles on first use against the freshly loaded grammar.
"""
function query_for(name::Symbol)
    return lock(CACHE_LOCK) do
        get!(QUERY_CACHE, name) do
            source = read(joinpath(QUERIES_DIR, "$(name).scm"), String)
            TreeSitter.Query(language_module(name), source)
        end
    end
end

# Compiled scopes queries cached per language, `nothing` for a language that ships
# none. Cached like `query_for`, so the missing-file check runs once.
const SCOPES_QUERY_CACHE = Dict{Symbol, Union{TreeSitter.Query, Nothing}}()

"""
    scopes_query_for(language) -> Union{TreeSitter.Query, Nothing}

The compiled lexical-scopes query for `language`, read from
`src/queries/<language>.scopes.scm`, or `nothing` when the language ships none. A
language without a scopes query carries no bindings, and the cohesion metric skips
it rather than treating every function as isolated.
"""
function scopes_query_for(name::Symbol)::Union{TreeSitter.Query, Nothing}
    return lock(CACHE_LOCK) do
        get!(SCOPES_QUERY_CACHE, name) do
            path = joinpath(QUERIES_DIR, "$(name).scopes.scm")
            isfile(path) || return nothing
            TreeSitter.Query(language_module(name), read(path, String))
        end
    end
end

# Compiled linkage queries cached per language, `nothing` for a language that ships
# none. Same lazy, cache-once shape as `scopes_query_for`.
const IMPORTS_QUERY_CACHE = Dict{Symbol, Union{TreeSitter.Query, Nothing}}()

"""
    imports_query_for(language) -> Union{TreeSitter.Query, Nothing}

The compiled linkage query for `language`, read from `src/queries/<language>.imports.scm`,
or `nothing` when the language ships none. It tags namespace regions (`@module`), import
and export statements, and `include`/`require` path strings, the captures the corpus
binding graph reads to resolve a reference across files.
"""
# Same lazy load and cache as `scopes_query_for`, differing only in the file kind, so
# the two share a shape with nothing left to extract.
# dendro-ignore: duplicate
function imports_query_for(name::Symbol)::Union{TreeSitter.Query, Nothing}
    return lock(CACHE_LOCK) do
        get!(IMPORTS_QUERY_CACHE, name) do
            path = joinpath(QUERIES_DIR, "$(name).imports.scm")
            isfile(path) || return nothing
            TreeSitter.Query(language_module(name), read(path, String))
        end
    end
end

# Populate every lazy per-language cache for `langs` before the corpus fan-outs, so no
# parallel task pays the JLL load or a query compile behind `CACHE_LOCK` mid fan-out.
function warm_languages(langs)
    for lang in langs
        parser_for(lang)
        query_for(lang)
        scopes_query_for(lang)
        imports_query_for(lang)
    end
    return nothing
end
