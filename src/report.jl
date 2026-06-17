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
    findings_for_tree(tree, profile, source, file; baseline, cut, within) -> Vector{Finding}

Collect findings for an already-parsed `tree`. Scalar metrics fire when they
breach their absolute band or, given a `baseline`, land at or above the `cut`
percentile. Flag metrics fire on presence. When `within` is a vector of line
ranges, only units overlapping a range and flags on a line in a range report,
the diff-scoped mode.
"""
function findings_for_tree(
    tree,
    profile::LanguageProfile,
    source::AbstractString,
    file::AbstractString;
    baseline::Union{Baseline,Nothing} = nothing,
    cut::Real = 0.95,
    within::Union{Vector{UnitRange{Int}},Nothing} = nothing,
)
    lang = profile.name
    out = Finding[]
    for unit in functions(tree, profile)
        within !== nothing && !intersects(within, unit.firstline, unit.lastline) && continue
        name = unit_name(unit, profile, source)
        metrics = unit_metrics(unit, profile, source)
        for metric in SCALAR_METRICS
            value = getfield(metrics, metric)
            band = severity(metric, value)
            pct = baseline === nothing ? nothing : percentile(baseline, lang, metric, value)
            if band != :ok || (pct !== nothing && pct >= cut)
                push!(out, Finding(file, unit.firstline, name, metric, value, band, pct, :scalar))
            end
        end
        if empty_body(unit.node, profile)
            push!(out, Finding(file, unit.firstline, name, :empty_body, nothing, :high, nothing, :flag))
        end
    end
    for node in empty_catches(tree, profile)
        line = line_of(node)
        within !== nothing && !inrange(within, line) && continue
        push!(out, Finding(file, line, "", :empty_catch, nothing, :high, nothing, :flag))
    end
    for node in stub_markers(tree, profile, source)
        line = line_of(node)
        within !== nothing && !inrange(within, line) && continue
        push!(out, Finding(file, line, "", :stub_marker, nothing, :high, nothing, :flag))
    end
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
    return findings_for_tree(tree, profile, source, path; baseline = baseline, cut = cut)
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
