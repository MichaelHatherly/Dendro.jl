# Findings and reporting. A Finding pairs a metric reading with the locations it
# covers and both scores, absolute (fixed band) and relative (corpus percentile).

"""
    Location

A code site: its `file` path, 1-based `line`, and enclosing `unit` name ("" when
no name node is found).
"""
struct Location
    file::String
    line::Int
    unit::String
end

"""
    Finding

One reported issue over one or more locations. Per-file metrics fire at a single
location; relational metrics like `:duplicate` span several.

- `metric`: which metric fired (`:cyclomatic`, `:empty_catch`, `:duplicate`, ...).
- `locations`: every site the finding covers, at least one.
- `value`: the scalar reading, the member count for `:duplicate`, or `nothing`.
- `absolute`: `:ok`/`:warn`/`:high` band, always `:high` for flags.
- `percentile`: corpus rank in `[0, 1]`, or `nothing` when no corpus sample ranks against it.
- `kind`: `:scalar` or `:flag`.
- `suppressed`: whether an inline directive accepted this finding.
"""
struct Finding
    metric::Symbol
    locations::Vector{Location}
    value::Union{Int,Nothing}
    absolute::Symbol
    percentile::Union{Float64,Nothing}
    kind::Symbol
    suppressed::Bool
end

# Single-location finding, the shape every per-file metric produces.
Finding(file, line, unit, metric, value, absolute, percentile, kind, suppressed) =
    Finding(metric, [Location(file, line, unit)], value, absolute, percentile, kind, suppressed)

# Label a function node by its name, or "" when no name node is found.
function unit_name(node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    name = ""
    TreeSitter.traverse(node) do n, enter
        if enter && isempty(name) && TreeSitter.node_type(n) in profile.name_types
            name = String(strip(TreeSitter.slice(source, n)))
        end
        nothing
    end
    return name
end

unit_name(unit::FunctionUnit, profile::LanguageProfile, source::AbstractString) =
    unit_name(unit.node, profile, source)

"""
    Scan

The fixed context for analysing one file: its `profile`, `source`, and `file`
path, the active `rules`, the optional `baseline` and `cut` percentile for
relative scoring, the optional `within` line ranges that restrict findings to a
diff, and the `directives` parsed from the source that suppress accepted findings.
"""
struct Scan
    profile::LanguageProfile
    source::String
    file::String
    rules::Vector{Rule}
    baseline::Union{Baseline,Nothing}
    cut::Float64
    within::Union{Vector{UnitRange{Int}},Nothing}
    directives::Vector{Directive}
end

Scan(profile, source, file; rules = BUILTIN_RULES, baseline = nothing, cut = 0.95, within = nothing, directives = Directive[]) =
    Scan(profile, String(source), String(file), rules, baseline, Float64(cut), within, directives)

# Whether a line span (or single line) is reported, given the scan's diff scope.
in_scope(scan::Scan, a::Int, b::Int) = scan.within === nothing || intersects(scan.within, a, b)
in_scope(scan::Scan, line::Int) = scan.within === nothing || inrange(scan.within, line)

# Scalar findings for one function unit, one per scalar rule that fires.
function unit_findings!(out, scan::Scan, unit::FunctionUnit)
    name = unit_name(unit, scan.profile, scan.source)
    for r in scalar_rules(scan.rules)
        value = r.fn(unit, scan.profile, scan.source)
        band = severity(value, r.band)
        pct = scan.baseline === nothing ? nothing :
              percentile(scan.baseline, scan.profile.name, r.name, value)
        outlier = pct !== nothing && pct >= scan.cut
        if band != :ok || outlier
            sup = is_suppressed(scan.directives, unit.firstline, r.name)
            push!(out, Finding(scan.file, unit.firstline, name, r.name, value, band, pct, :scalar, sup))
        end
    end
    return out
end

# Flag findings for a set of nodes, all reported with the same metric. A node
# that is itself a function unit is labelled with its name; other nodes are not.
function flag_findings!(out, scan::Scan, nodes, metric::Symbol)
    for node in nodes
        line = line_of(node)
        in_scope(scan, line) || continue
        name = TreeSitter.node_type(node) in scan.profile.function_types ?
               unit_name(node, scan.profile, scan.source) : ""
        sup = is_suppressed(scan.directives, line, metric)
        push!(out, Finding(scan.file, line, name, metric, nothing, :high, nothing, :flag, sup))
    end
    return out
end

"""
    findings_for_tree(tree, scan) -> Vector{Finding}

Collect findings for an already-parsed `tree`. Scalar metrics fire when they
breach their absolute band or, given a baseline, land at or above the cut
percentile. Flag metrics fire on presence. A diff-scoped `scan` reports only
units overlapping a changed range and flags on a changed line.
"""
function findings_for_tree(tree, scan::Scan)
    out = Finding[]
    for unit in functions(tree, scan.profile)
        in_scope(scan, unit.firstline, unit.lastline) || continue
        unit_findings!(out, scan, unit)
    end
    for r in flag_rules(scan.rules)
        flag_findings!(out, scan, r.fn(tree, scan.profile, scan.source), r.name)
    end
    return out
end

"""
    Findings <: AbstractVector{Finding}

The result of [`analyze`](@ref): the findings it produced, printed as a report.
Behaves as an `AbstractVector{Finding}`, so it iterates, filters, and indexes like
any vector of [`Finding`](@ref)s.
"""
struct Findings <: AbstractVector{Finding}
    items::Vector{Finding}
end

Base.size(fs::Findings) = size(fs.items)
Base.getindex(fs::Findings, i::Int) = fs.items[i]
Base.IndexStyle(::Type{Findings}) = IndexLinear()

"""
    active(findings) -> Findings

The findings not suppressed by an inline directive. Use this for gating.
"""
active(findings) = Findings(filter(f -> !f.suppressed, findings))

# The score column shared by every renderer: the absolute band, plus the corpus
# percentile when one ranks the value.
function score_suffix(f::Finding)
    rel = f.percentile === nothing ? "" : string("; p", round(Int, f.percentile * 100))
    return string("(", f.absolute, rel, ")")
end

# The REPL display for the `Findings` `analyze` returns. Each finding prints as
# `file:line  unit  metric value (scores)`, with an `also at` line per extra
# location, and a trailing count of findings suppressed by directives so
# suppressions stay visible rather than silently dropped.
function Base.show(io::IO, ::MIME"text/plain", findings::Findings)
    suppressed = shown = 0
    for f in findings
        if f.suppressed
            suppressed += 1
            continue
        end
        anchor = first(f.locations)
        loc = string(anchor.file, ":", anchor.line)
        label = isempty(anchor.unit) ? "" : string("  ", anchor.unit)
        val = f.value === nothing ? "" : string(" ", f.value)
        println(io, loc, label, "  ", f.metric, val, " ", score_suffix(f))
        for extra in Iterators.drop(f.locations, 1)
            tag = isempty(extra.unit) ? "" : string("  ", extra.unit)
            println(io, "    also at ", extra.file, ":", extra.line, tag)
        end
        shown += 1
    end
    shown == 0 && suppressed == 0 && println(io, "No findings.")
    suppressed > 0 && println(io, suppressed, " finding(s) suppressed by directives")
    return nothing
end

# GitHub Actions workflow commands escape `%`, `\r`, `\n` in a message, and
# additionally `:` and `,` in a property value, so neither breaks the line.
escape_data(s::AbstractString) = replace(s, "%" => "%25", "\r" => "%0D", "\n" => "%0A")
escape_prop(s::AbstractString) = replace(escape_data(s), ":" => "%3A", "," => "%2C")

# The single-line message for one finding: `unit: metric value (scores)`, with a
# trailing `; also at file:line` per extra location so a multi-site finding names
# its other members where annotations are line-anchored.
function annotation_message(f::Finding)
    anchor = first(f.locations)
    prefix = isempty(anchor.unit) ? "" : string(anchor.unit, ": ")
    val = f.value === nothing ? "" : string(" ", f.value)
    msg = string(prefix, f.metric, val, " ", score_suffix(f))
    for extra in Iterators.drop(f.locations, 1)
        msg = string(msg, "; also at ", extra.file, ":", extra.line)
    end
    return msg
end

"""
    github_annotations(io, findings)
    github_annotations(findings)

Write `findings` as GitHub Actions workflow commands, one `::error`/`::warning`
line per finding, anchored at its first location. GitHub renders each as an inline
annotation on the matching diff line, so pair this with `analyze`'s `base` to scope
to changed lines. Suppressed findings are omitted. High-band findings map to
`::error`, the rest to `::warning`.
"""
function github_annotations(io::IO, findings::Findings)
    for f in findings
        f.suppressed && continue
        anchor = first(f.locations)
        level = f.absolute === :high ? "error" : "warning"
        title = string("Dendro: ", f.metric)
        println(io, "::", level, " file=", escape_prop(anchor.file),
                ",line=", anchor.line, ",title=", escape_prop(title),
                "::", escape_data(annotation_message(f)))
    end
    return nothing
end

github_annotations(findings::Findings) = github_annotations(stdout, findings)
