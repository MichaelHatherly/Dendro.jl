# Corpus distribution for relative scoring. A value's percentile rank against
# the corpus says whether a function is worse than the codebase's own norm,
# the signal that complements the fixed absolute bands.

"""
    Baseline

Per `(language, metric)` sorted samples of scalar-metric values drawn from a
corpus.
"""
struct Baseline
    samples::Dict{Tuple{Symbol, Symbol}, Vector{Float64}}
end

Baseline() = Baseline(Dict{Tuple{Symbol, Symbol}, Vector{Float64}}())

# Accumulate one tree's scalar-metric values into a baseline, keyed by language.
function add_samples!(baseline::Baseline, index::QueryIndex, rules = BUILTIN_RULES)
    for unit in functions(index)
        for r in rules_of_kind(rules, :scalar)
            samples = get!(() -> Float64[], baseline.samples, (index.language, r.name))
            push!(samples, Float64(r.fn(unit, index)::Int))
        end
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
