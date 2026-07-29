# User-authored lint rules as a second query family. `<lang>.scm` captures name the
# concepts every metric reads, a closed set. A `<lang>.patterns.scm` capture names a
# *rule*, an open set written against concrete grammar node types on purpose, since
# being language-specific is the point. The two never merge: merging takes `dispatch!`'s
# closure with it and metric code starts special-casing languages.
#
# A rule is declared once in `.dendro.toml`, language-independently, and realised per
# language by a query. The declaration carries what the finding says and how loud it is;
# the query carries the shape. [`PatternSpec`](@ref) is the declaration and lives in
# `rules.jl` beside `Rule`, since `Config` holds a vector of them; everything here is what
# turns one into findings.

# Coerce a TOML value naming one of a fixed set of symbols. Unlike an unknown key, which
# warns and is dropped, a bad value here is an error: the author clearly meant to set it,
# and guessing which of two severities they wanted would be worse than stopping.
function pattern_symbol(value, allowed, key, rule, source)::Symbol
    value isa AbstractString || config_error("`$key` for pattern `$rule` in $source must be a string, got $value")
    sym = Symbol(value)
    sym in allowed && return sym
    names = join(("`$a`" for a in allowed), ", ")
    return config_error("`$key` for pattern `$rule` in $source must be one of $names, got `$value`")
end

# Apply one `[patterns.<name>]` table. Only `message` is required; `severity` and `kind`
# default, and `band` is required by a scalar and rejected on a flag. An unknown key warns
# and is dropped, as a band does.
function apply_pattern!(acc, name::String, table::Dict{String, Any}, source)
    message = ""
    severity = :warn
    kind = :flag
    band = nothing
    for (key, value) in table
        if key == "message"
            message = config_string(value, "patterns.$name.$key", source)
        elseif key == "severity"
            severity = pattern_symbol(value, PATTERN_SEVERITIES, key, name, source)
        elseif key == "kind"
            kind = pattern_symbol(value, PATTERN_KINDS, key, name, source)
        elseif key == "band"
            band = band_tuple(value, "patterns.$name.$key", source)
        else
            @warn "Dendro: unknown pattern key in $source, ignored" pattern = name key
        end
    end
    isempty(message) && config_error("pattern `$name` in $source needs a `message`")
    validate_pattern_band(name, kind, band, source)
    acc.patterns[Symbol(name)] = PatternSpec(Symbol(name), message, severity, kind, band)
    return nothing
end

# A flag scores nothing, so a band on one is a declaration the author misunderstood. A
# scalar without a band has no absolute score at all. A scalar band starting below 1 lets
# `severity(0, band)` return something other than `:ok`, which would report every unit in
# the corpus for holding no matches.
function validate_pattern_band(name, kind::Symbol, band, source)
    if kind === :flag
        band === nothing || config_error("pattern `$name` in $source is a flag and cannot carry a `band`")
    else
        band === nothing && config_error("pattern `$name` in $source is a scalar and needs a `band`")
        first(band) >= 1 ||
            config_error("band for pattern `$name` in $source must start at 1 or higher, got $(first(band))")
    end
    return nothing
end

# `apply_patterns!`, the `[patterns]` table walk, lives in `config.jl` beside the
# `[languages]` one: the two differ only in the key prefix and the per-entry applier, so
# they share `apply_named_tables!`. What is pattern-specific is `apply_pattern!` above.

# --- Where the queries live ---------------------------------------------------------
#
# Two locations, both read and composed: a repo's own rules and the house rules a
# developer shares across repositories. Separate from `[languages].queries`, which
# replaces a whole language profile, so adding one lint rule cannot cost a language its
# scopes query and every binding-based flag.

# The repo-relative default, under the directory holding `.dendro.toml`.
const DEFAULT_PATTERNS_DIR = joinpath(".dendro", "patterns")

"""
    pattern_dirs(config, roots) -> Vector{String}

The directories holding `<lang>.patterns.scm`, in cascade order: the user-global one
first, then the repo's, so a rule defined in both resolves to the repo's.

A `patterns_dir` set in a config file is resolved against that file's own directory, not
the process working directory, so running `dendro` from a subdirectory keeps working.
"""
function pattern_dirs(config::Config, roots)::Vector{String}
    dirs = String[]
    global_dir = joinpath(dirname(global_config_path()), "patterns")
    isdir(global_dir) && push!(dirs, global_dir)
    repo = isempty(config.patterns_dir) ? repo_pattern_dir(roots) : config.patterns_dir
    repo !== nothing && isdir(repo) && push!(dirs, repo)
    return dirs
end

# The repo's own pattern directory: `.dendro/patterns` under the directory a
# `.dendro.toml` would be discovered in. `nothing` when there is no such directory to
# anchor against.
function repo_pattern_dir(roots)
    dir = repo_config_dir(roots)
    return dir === nothing ? nothing : joinpath(dir, DEFAULT_PATTERNS_DIR)
end

# --- Compiling a rule query ---------------------------------------------------------
#
# Tree-sitter checks a query's node types, field names, and capture references when it
# compiles, so a query naming a shape the grammar does not have fails here rather than
# reporting nothing at review time. That checking is the reason rules are queries and not
# Julia functions: a Julia rule matching on node-type strings is checked by nothing.
#
# The one gap is predicates. TreeSitter.jl warns on an unknown one and then rejects every
# match, so a rule using `#not-any-of?` reads as clean code. `PATTERN_PREDICATES` closes
# it at load.

# The predicates TreeSitter.jl 0.2 implements, read off its `predicate` dispatch. A query
# naming anything else compiles and then silently rejects every match, so it is rejected
# here instead. `not-any-of?` and `not-has-ancestor?` are the two commonly reached for
# that do not exist; the `.not` capture covers both.
const PATTERN_PREDICATES = Set{String}(
    [
        "eq?", "not-eq?", "any-of?", "has-ancestor?", "is?", "is-not?", "match?",
        "not-match?", "any-eq?", "any-not-eq?", "any-match?", "any-not-match?", "set!",
    ]
)

# A predicate call in query text: `(#name? ...`. Predicate names are syntactically
# distinctive, and the C API does not expose them by name before a match is evaluated, so
# reading them off the source is the only way to check one at load.
const PREDICATE_RE = r"\(\s*#([\w!?.-]+)"

"""
    pattern_query_source(dir, language) -> Union{String, Nothing}

The text of `dir/<language>.patterns.scm`, or `nothing` when the file is absent. A
language with no file for a rule simply never fires it, which is not an error: a rule is
declared once and realised per grammar, and no project writes every grammar.
"""
function pattern_query_source(dir::AbstractString, language::Symbol)
    path = joinpath(dir, "$(language).patterns.scm")
    return isfile(path) ? read(path, String) : nothing
end

# 1-based line holding byte offset `offset` in `text`, for turning a `QueryException`'s
# index into something a rule author can navigate to.
line_at_offset(text::AbstractString, offset::Integer) =
    count(==('\n'), SubString(text, 1, min(max(offset, 0), ncodeunits(text)))) + 1

# The byte offset a `QueryException` names. Its message is
# `"'<kind>' error starting at index <n>"` and it carries nothing else, so the offset is
# recovered from the text rather than from a field.
function query_error_offset(e)
    m = match(r"at index (\d+)", e.msg)
    return m === nothing ? 0 : parse(Int, m.captures[1])
end

# The error kind a `QueryException` names: `node type`, `field`, `capture`, `syntax`.
function query_error_kind(e)
    m = match(r"'([^']+)'", e.msg)
    return m === nothing ? "query" : m.captures[1]
end

"""
    compile_pattern_query(grammar, source, path) -> TreeSitter.Query

Compile one `<lang>.patterns.scm`, reporting a malformed query as a [`ConfigError`](@ref)
naming the file and the line rather than a `QueryException` carrying a byte offset.

Predicates are checked against [`PATTERN_PREDICATES`](@ref) first: an unimplemented one
compiles cleanly and then rejects every match, so a rule using one would report nothing
and read as clean code.
"""
function compile_pattern_query(grammar, source::AbstractString, path::AbstractString)
    check_predicates(source, path)
    try
        return TreeSitter.Query(grammar, source)
    catch e
        e isa TreeSitter.QueryException || rethrow()
        line = line_at_offset(source, query_error_offset(e))
        config_error("$(query_error_kind(e)) error at line $line of $path")
    end
end

# Reject a predicate TreeSitter.jl does not implement, naming the alternatives, since a
# reader hitting this needs to know what to use instead.
function check_predicates(source::AbstractString, path::AbstractString)
    for m in eachmatch(PREDICATE_RE, source)
        name = m.captures[1]
        name in PATTERN_PREDICATES && continue
        line = line_at_offset(source, m.offset - 1)
        available = join(sort!(collect(PATTERN_PREDICATES)), ", ")
        config_error(
            "unknown predicate `#$name` at line $line of $path. Available: $available"
        )
    end
    return nothing
end
