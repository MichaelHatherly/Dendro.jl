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
- `percentile`: corpus rank in `[0, 1]`, or `nothing` without a baseline.
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

# Label a function unit by its name, or "" when no name node is found.
function unit_name(unit::FunctionUnit, profile::LanguageProfile, source::AbstractString)
    name = ""
    TreeSitter.traverse(unit.node) do n, enter
        if enter && isempty(name) && TreeSitter.node_type(n) in profile.name_types
            name = String(strip(TreeSitter.slice(source, n)))
        end
        nothing
    end
    return name
end

"""
    Scan

The fixed context for analysing one file: its `profile`, `source`, and `file`
path, the optional `baseline` and `cut` percentile for relative scoring, and the
optional `within` line ranges that restrict findings to a diff, and the
`directives` parsed from the source that suppress accepted findings.
"""
struct Scan
    profile::LanguageProfile
    source::String
    file::String
    baseline::Union{Baseline,Nothing}
    cut::Float64
    within::Union{Vector{UnitRange{Int}},Nothing}
    directives::Vector{Directive}
end

Scan(profile, source, file; baseline = nothing, cut = 0.95, within = nothing, directives = Directive[]) =
    Scan(profile, String(source), String(file), baseline, Float64(cut), within, directives)

# Whether a line span (or single line) is reported, given the scan's diff scope.
in_scope(scan::Scan, a::Int, b::Int) = scan.within === nothing || intersects(scan.within, a, b)
in_scope(scan::Scan, line::Int) = scan.within === nothing || inrange(scan.within, line)

# Scalar and empty-body findings for one function unit.
function unit_findings!(out, scan::Scan, unit::FunctionUnit)
    name = unit_name(unit, scan.profile, scan.source)
    metrics = unit_metrics(unit, scan.profile, scan.source)
    for metric in SCALAR_METRICS
        value = getfield(metrics, metric)
        band = severity(metric, value)
        pct = scan.baseline === nothing ? nothing :
              percentile(scan.baseline, scan.profile.name, metric, value)
        outlier = pct !== nothing && pct >= scan.cut
        if band != :ok || outlier
            sup = is_suppressed(scan.directives, unit.firstline, metric)
            push!(out, Finding(scan.file, unit.firstline, name, metric, value, band, pct, :scalar, sup))
        end
    end
    if empty_body(unit.node, scan.profile)
        sup = is_suppressed(scan.directives, unit.firstline, :empty_body)
        push!(out, Finding(scan.file, unit.firstline, name, :empty_body, nothing, :high, nothing, :flag, sup))
    end
    return out
end

# Flag findings for a set of nodes, all reported with the same metric.
function flag_findings!(out, scan::Scan, nodes, metric::Symbol)
    for node in nodes
        line = line_of(node)
        in_scope(scan, line) || continue
        sup = is_suppressed(scan.directives, line, metric)
        push!(out, Finding(scan.file, line, "", metric, nothing, :high, nothing, :flag, sup))
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
    flag_findings!(out, scan, empty_catches(tree, scan.profile), :empty_catch)
    flag_findings!(out, scan, stub_markers(tree, scan.profile, scan.source), :stub_marker)
    return out
end

"""
    analyze(path; language=nothing, baseline=nothing, cut=0.95) -> Vector{Finding}

Parse `path` and report its findings. The language is inferred from the file
extension unless given as a symbol or string.
"""
function analyze(path::AbstractString; language = nothing, baseline = nothing, cut::Real = 0.95)
    lang = language === nothing ? language_for_path(path) :
           Symbol(lowercase(String(language)))
    lang === nothing && error("Dendro: cannot infer language for $path; pass `language=`.")
    haskey(PROFILES, lang) || error("Dendro: no profile for language :$lang.")
    profile = PROFILES[lang]
    source = read(path, String)
    tree = parse(parser_for(lang), source)
    dirs = suppressions(tree, profile, source; file = path)
    scan = Scan(profile, source, path; baseline = baseline, cut = cut, directives = dirs)
    return findings_for_tree(tree, scan)
end

"""
    active(findings) -> Vector{Finding}

The findings not suppressed by an inline directive. Use this for gating.
"""
active(findings) = filter(f -> !f.suppressed, findings)

"""
    report([io], findings)

Write each finding as `file:line  unit  metric value (scores)`, followed by an
`also at` line per extra location for findings that span several.
"""
function report(io::IO, findings)
    suppressed = 0
    for f in findings
        if f.suppressed
            suppressed += 1
            continue
        end
        anchor = first(f.locations)
        loc = string(anchor.file, ":", anchor.line)
        label = isempty(anchor.unit) ? "" : string("  ", anchor.unit)
        val = f.value === nothing ? "" : string(" ", f.value)
        rel = f.percentile === nothing ? "" : string("; p", round(Int, f.percentile * 100))
        println(io, loc, label, "  ", f.metric, val, " (", f.absolute, rel, ")")
        for extra in Iterators.drop(f.locations, 1)
            tag = isempty(extra.unit) ? "" : string("  ", extra.unit)
            println(io, "    also at ", extra.file, ":", extra.line, tag)
        end
    end
    suppressed > 0 && println(io, suppressed, " finding(s) suppressed by directives")
    return nothing
end
report(findings) = report(stdout, findings)
