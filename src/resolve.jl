# Language identification and lazy parser resolution.

# File extension to language name. Languages match TreeSitter.jl's supported set.
const EXTENSIONS = Dict{String, Symbol}(
    "jl" => :julia,
    "py" => :python,
    "sh" => :bash,
    "bash" => :bash,
    "c" => :c,
    "h" => :c,
    "cpp" => :cpp,
    "cc" => :cpp,
    "cxx" => :cpp,
    "hpp" => :cpp,
    "hh" => :cpp,
    "hxx" => :cpp,
    "go" => :go,
    "html" => :html,
    "htm" => :html,
    "java" => :java,
    "js" => :javascript,
    "mjs" => :javascript,
    "cjs" => :javascript,
    "jsx" => :javascript,
    "json" => :json,
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
    return Base.require(id)
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
    return get!(QUERY_CACHE, name) do
        source = read(joinpath(QUERIES_DIR, "$(name).scm"), String)
        TreeSitter.Query(language_module(name), source)
    end
end
