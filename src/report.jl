# Findings and reporting. A Finding pairs a metric reading with its location and
# both scores, absolute (fixed band) and relative (corpus percentile).

"""
    Finding

One reported issue.

- `metric`: which metric fired (`:cyclomatic`, `:empty_catch`, ...).
- `value`: the scalar reading, or `nothing` for flag metrics.
- `absolute`: `:ok`/`:warn`/`:high` band, always `:high` for flags.
- `percentile`: corpus rank in `[0, 1]`, or `nothing` without a baseline.
- `kind`: `:scalar` or `:flag`.
"""
struct Finding
    file::String
    line::Int
    unit::String
    metric::Symbol
    value::Union{Int,Nothing}
    absolute::Symbol
    percentile::Union{Float64,Nothing}
    kind::Symbol
end

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

line_of(node) = Int(TreeSitter.start_point(node).row) + 1

"""
    Scan

The fixed context for analysing one file: its `profile`, `source`, and `file`
path, the optional `baseline` and `cut` percentile for relative scoring, and the
optional `within` line ranges that restrict findings to a diff.
"""
struct Scan
    profile::LanguageProfile
    source::String
    file::String
    baseline::Union{Baseline,Nothing}
    cut::Float64
    within::Union{Vector{UnitRange{Int}},Nothing}
end

Scan(profile, source, file; baseline = nothing, cut = 0.95, within = nothing) =
    Scan(profile, String(source), String(file), baseline, Float64(cut), within)

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
            push!(out, Finding(scan.file, unit.firstline, name, metric, value, band, pct, :scalar))
        end
    end
    if empty_body(unit.node, scan.profile)
        push!(out, Finding(scan.file, unit.firstline, name, :empty_body, nothing, :high, nothing, :flag))
    end
    return out
end

# Flag findings for a set of nodes, all reported with the same metric.
function flag_findings!(out, scan::Scan, nodes, metric::Symbol)
    for node in nodes
        line = line_of(node)
        in_scope(scan, line) && push!(out, Finding(scan.file, line, "", metric, nothing, :high, nothing, :flag))
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
           language isa Symbol ? language : Symbol(lowercase(String(language)))
    lang === nothing && error("Dendro: cannot infer language for $path; pass `language=`.")
    haskey(PROFILES, lang) || error("Dendro: no profile for language :$lang.")
    profile = PROFILES[lang]
    source = read(path, String)
    tree = parse(parser_for(lang), source)
    return findings_for_tree(tree, Scan(profile, source, path; baseline = baseline, cut = cut))
end

"""
    report([io], findings)

Write `findings` as one line each: `file:line  unit  metric value (scores)`.
"""
function report(io::IO, findings)
    for f in findings
        loc = string(f.file, ":", f.line)
        label = isempty(f.unit) ? "" : string("  ", f.unit)
        if f.kind == :scalar
            rel = f.percentile === nothing ? "" : string("; p", round(Int, f.percentile * 100))
            println(io, loc, label, "  ", f.metric, " ", f.value, " (", f.absolute, rel, ")")
        else
            println(io, loc, label, "  ", f.metric, " (", f.absolute, ")")
        end
    end
    return nothing
end
report(findings) = report(stdout, findings)
