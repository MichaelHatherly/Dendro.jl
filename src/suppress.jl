# Inline suppression directives. A comment in the source accepts a specific
# finding the author judged fine in context, so Dendro can skip it without the
# author muting the tool or refactoring sound code.

"""
    Directive

One parsed suppression. `scope` is the comment's line number, or `:file` for a
whole-file directive. `metrics` is the set of metric names it covers, or
`nothing` for all metrics.
"""
struct Directive
    scope::Union{Int,Symbol}
    metrics::Union{Nothing,Set{Symbol}}
end

# Metric names a directive may name. Dendro's own, in the syntax authors write.
const METRICS = (SCALAR_METRICS..., :empty_body, :empty_catch, :stub_marker)

# `dendro-ignore` or `dendro-ignore-file`, with an optional `: metric, metric`
# list. Case-insensitive, matched anywhere in a comment's text.
const DIRECTIVE_RE = r"\bdendro-ignore(-file)?\b(?:\s*:\s*([\w,\s]+))?"i

# 1-based source line of a node's first character.
line_of(node) = Int(TreeSitter.start_point(node).row) + 1

# Parse the metric-list capture into a validated set, warning on unknown names.
function parse_metrics(list::AbstractString, file, line)
    metrics = Set{Symbol}()
    for token in split(list, ',')
        name = strip(token)
        isempty(name) && continue
        sym = Symbol(name)
        if sym in METRICS
            push!(metrics, sym)
        else
            @warn "Dendro: unknown metric in suppression directive" file line token = name
        end
    end
    return metrics
end

"""
    suppressions(tree, profile, source; file) -> Vector{Directive}

Scan every comment node for `dendro-ignore` directives and return one
`Directive` per match. A `-file` directive carries `:file` scope, others carry
the comment's line. Named metrics are validated against [`METRICS`]; an unknown
name warns and is dropped.
"""
function suppressions(tree, profile::LanguageProfile, source::AbstractString; file)
    out = Directive[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.comment_types
            text = TreeSitter.slice(source, n)
            for m in eachmatch(DIRECTIVE_RE, text)
                scope = m.captures[1] === nothing ? line_of(n) : :file
                metrics = m.captures[2] === nothing ? nothing :
                          parse_metrics(m.captures[2], file, line_of(n))
                push!(out, Directive(scope, metrics))
            end
        end
        nothing
    end
    return out
end

"""
    is_suppressed(directives, line, metric) -> Bool

True when a directive accepts `metric` at `line`: file scope, the same line, or
the line directly above, with a metric set that is `nothing` or contains
`metric`.
"""
function is_suppressed(directives, line::Int, metric::Symbol)
    for d in directives
        covers = d.scope === :file || d.scope == line || d.scope == line - 1
        covers || continue
        (d.metrics === nothing || metric in d.metrics) && return true
    end
    return false
end
