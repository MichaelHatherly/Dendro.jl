# Factoring a repeated pattern out of a rule query.
#
# Tree-sitter queries have no include or macro form, so a project writing several rules
# about the same construct repeats its shape in each. `julia.scm` repeats its parameter
# patterns five times for exactly this reason.
#
# A fragment is a named piece of query text, defined in a comment and expanded where it is
# referenced:
#
#     ; fragment: signature = [(call_expression) (typed_expression (call_expression))]
#     (function_definition (signature @signature)) @needs_docstring
#
# The constraint the whole design answers to: load-time validation is why rules are queries
# rather than Julia functions, and an error reported at an offset into text the author never
# wrote would destroy it. So expansion is line-preserving, and every expanded span is
# recorded, letting a `QueryException` inside one name the fragment, where it was defined,
# and where it was used. If that could not be made to work, this feature would not ship.

# A fragment definition line: `; fragment: <name> = <query text>`, to end of line.
const FRAGMENT_DEF_RE = r"^[ \t]*;[ \t]*fragment:[ \t]*([A-Za-z_][\w]*)[ \t]*=[ \t]*(.*)$"m

# A reference to a fragment or a capture. Which one it is depends on whether the name has
# been defined as a fragment, so the two share a sigil and are told apart by the table.
const FRAGMENT_REF_RE = r"@([A-Za-z_][\w]*)"

"""
    Fragment

One named piece of query text and the 1-based line its definition sits on, so an error
inside its expansion can name where to go and fix it.
"""
struct Fragment
    name::String
    text::String
    line::Int
end

"""
    ExpandedQuery

Query text with every fragment reference expanded, plus the map back to where each expanded
byte came from. `spans` pairs a byte range in `text` with the fragment that produced it, in
ascending order, so a byte offset resolves by search rather than by scanning.

`text` preserves the line structure of the source it came from: a definition line becomes a
blank comment and a reference expands within its own line, so any offset outside a span
reports the line it really sits on.
"""
struct ExpandedQuery
    text::String
    spans::Vector{Tuple{UnitRange{Int}, Fragment}}
    used_at::Dict{String, Int}
end

ExpandedQuery(text::AbstractString) =
    ExpandedQuery(String(text), Tuple{UnitRange{Int}, Fragment}[], Dict{String, Int}())

"""
    collect_fragments(source, path) -> Dict{String, Fragment}

Every `; fragment:` definition in `source`, keyed by name. A name defined twice is a
`ConfigError`: silently taking the last would make the file's meaning depend on its order
in a way nothing else in the format does.
"""
function collect_fragments(source::AbstractString, path::AbstractString)
    out = Dict{String, Fragment}()
    for m in eachmatch(FRAGMENT_DEF_RE, source)
        name = String(m.captures[1])
        line = line_at_offset(source, m.offset - 1)
        haskey(out, name) && config_error(
            "fragment `$name` at line $line of $path is already defined at line $(out[name].line)"
        )
        out[name] = Fragment(name, strip(String(m.captures[2])), line)
    end
    return out
end

# Blank out the definition lines, keeping the newlines so every later line keeps its number.
# The definitions have been read into the table by this point and are not query syntax.
strip_fragment_defs(source::AbstractString) =
    replace(source, FRAGMENT_DEF_RE => s -> "")

"""
    expand_fragments(source, path) -> ExpandedQuery

`source` with every fragment reference replaced by its definition, carrying the map from
expanded bytes back to the fragment that produced them.

Expansion is one level: a fragment's own text is inserted verbatim, and a reference inside a
fragment is left alone rather than expanded recursively. A rule needing that is a rule that
wants a macro language, which is a larger idea than this and would take the error story with
it.
"""
function expand_fragments(source::AbstractString, path::AbstractString)
    fragments = collect_fragments(source, path)
    isempty(fragments) && return ExpandedQuery(source)

    stripped = strip_fragment_defs(source)
    io = IOBuffer()
    spans = Tuple{UnitRange{Int}, Fragment}[]
    used_at = Dict{String, Int}()
    last = 1
    for m in eachmatch(FRAGMENT_REF_RE, stripped)
        frag = get(fragments, String(m.captures[1]), nothing)
        frag === nothing && continue
        write(io, SubString(stripped, last, prevind(stripped, m.offset)))
        from = position(io) + 1
        write(io, frag.text)
        push!(spans, (from:position(io), frag))
        get!(used_at, frag.name, line_at_offset(stripped, m.offset - 1))
        last = m.offset + ncodeunits(m.match)
    end
    write(io, SubString(stripped, last, lastindex(stripped)))
    return ExpandedQuery(String(take!(io)), spans, used_at)
end

"""
    error_site(expanded, offset, path) -> String

Where byte `offset` of an expanded query really came from, phrased for a rule author.

Inside an expansion this names the fragment, the line it was defined on, and the line it was
used on. Outside one it names the file and line directly, which is the same thing an
unexpanded query reports.
"""
function error_site(expanded::ExpandedQuery, offset::Integer, path::AbstractString)
    for (range, frag) in expanded.spans
        offset in range || continue
        at = get(expanded.used_at, frag.name, 0)
        return "fragment `$(frag.name)` (defined at line $(frag.line), used at line $at) of $path"
    end
    return "line $(line_at_offset(expanded.text, offset)) of $path"
end

"""
    check_fragment_names(fragments, specs, path)

Reject a fragment whose name is also a declared rule. The two share the `@` sigil, so
`@signature` cannot mean both a rule to report and a shape to splice, and guessing which was
meant would be worse than stopping.
"""
function check_fragment_names(fragments, specs, path::AbstractString)
    declared = Set(s.name for s in specs)
    for (name, frag) in fragments
        Symbol(name) in declared && config_error(
            "fragment `$name` at line $(frag.line) of $path has the same name as a declared " *
                "rule. Rename one: a capture cannot be both a rule and a fragment"
        )
    end
    return nothing
end
