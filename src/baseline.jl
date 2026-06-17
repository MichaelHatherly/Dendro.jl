# Corpus distribution for relative scoring. A value's percentile rank against
# the corpus says whether a function is worse than the codebase's own norm,
# the signal that complements the fixed absolute bands.

"""
    Baseline

Per `(language, metric)` sorted samples of scalar-metric values drawn from a
corpus.
"""
struct Baseline
    samples::Dict{Tuple{Symbol,Symbol},Vector{Float64}}
end

Baseline() = Baseline(Dict{Tuple{Symbol,Symbol},Vector{Float64}}())

"""
    build_baseline(paths) -> Baseline

Parse each file in `paths`, compute scalar metrics for every function, and
collect them per `(language, metric)`. Files whose language has no profile are
skipped.
"""
function build_baseline(paths)
    baseline = Baseline()
    parsers = Dict{Symbol,TreeSitter.Parser}()
    for path in paths
        lang = language_for_path(path)
        (lang === nothing || !haskey(PROFILES, lang)) && continue
        profile = PROFILES[lang]
        parser = get!(() -> parser_for(lang), parsers, lang)
        source = read(path, String)
        tree = parse(parser, source)
        for unit in functions(tree, profile)
            metrics = unit_metrics(unit, profile, source)
            for metric in SCALAR_METRICS
                samples = get!(() -> Float64[], baseline.samples, (lang, metric))
                push!(samples, Float64(getfield(metrics, metric)))
            end
        end
    end
    for samples in values(baseline.samples)
        sort!(samples)
    end
    return baseline
end

"""
    percentile(baseline, language, metric, value) -> Union{Float64,Nothing}

Fraction of corpus samples for `(language, metric)` at or below `value`, or
`nothing` when the corpus holds no samples to rank against.
"""
function percentile(baseline::Baseline, language::Symbol, metric::Symbol, value::Real)
    samples = get(baseline.samples, (language, metric), nothing)
    (samples === nothing || isempty(samples)) && return nothing
    return searchsortedlast(samples, value) / length(samples)
end

"""
    save_baseline(baseline, path) -> path

Write `baseline` to `path` as JSON.
"""
function save_baseline(baseline::Baseline, path::AbstractString)
    entries = [
        Dict("language" => String(lang), "metric" => String(metric), "samples" => samples)
        for ((lang, metric), samples) in baseline.samples
    ]
    open(io -> JSON.print(io, entries), path, "w")
    return path
end

"""
    load_baseline(path) -> Baseline

Read a baseline previously written by [`save_baseline`](@ref).
"""
function load_baseline(path::AbstractString)
    samples = Dict{Tuple{Symbol,Symbol},Vector{Float64}}()
    for entry in JSON.parsefile(path)
        key = (Symbol(entry["language"]), Symbol(entry["metric"]))
        samples[key] = Float64.(entry["samples"])
    end
    return Baseline(samples)
end
