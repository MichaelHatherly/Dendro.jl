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
    for unit in units(index)
        for r in rules_of_kind(rules, :scalar)
            # The same gate the scoring pass reads. A rule that says nothing about a unit
            # must not sample it either, or top-level readings would move the percentile a
            # definition is then ranked against.
            applies(r, unit, index) || continue
            samples = get!(() -> Float64[], baseline.samples, (index.language, r.name))
            push!(samples, Float64(r.fn(unit, index)::Int))
        end
    end
    return baseline
end

# Baseline over already-parsed corpus records. Each chunk samples into its own partial
# baseline; the merge concatenates per `(language, metric)` and the final `sort!` fixes the
# order, so the sorted samples are identical to the serial path at any thread count.
function baseline_from(files::Vector{ParsedFile}, rules = BUILTIN_RULES)
    partials = parallel_chunks(() -> Baseline(), length(files)) do baseline, idxs
        sample_chunk!(baseline, files, idxs, rules)
    end
    baseline = merge_baselines(partials)
    for samples in values(baseline.samples)
        sort!(samples)
    end
    return baseline
end

# Sample one chunk of files into a partial baseline.
function sample_chunk!(baseline::Baseline, files::Vector{ParsedFile}, idxs, rules)
    for i in idxs
        add_samples!(baseline, files[i].index, rules)
    end
    return baseline
end

# Concatenate partial baselines per `(language, metric)`. The caller sorts the merged
# samples, so the append order does not affect the result.
function merge_baselines(partials::Vector{Baseline})
    merged = Baseline()
    for p in partials
        for (k, v) in p.samples
            append!(get!(() -> Float64[], merged.samples, k), v)
        end
    end
    return merged
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

# --- The percentile guard -------------------------------------------------------------
#
# A percentile only says something when the corpus spreads out under it. For a metric that
# is zero across most of a codebase the rank degenerates: at the extreme, a unit holding no
# matches sits above the cut and `fires` reports a function for containing nothing.
#
# The test is `pct@1`, the percentile a unit holding exactly one occurrence is assigned.
# When that already breaches the cut, every unit with a single occurrence fires on rank
# alone and the rank has stopped ranking. One `searchsortedlast` against the sorted samples
# decides it, and the absolute band is untouched either way: this decides whether the rank
# is read, never what the fixed band says.

"""
    percentile_informs(baseline, language, metric, cut) -> Bool

Whether `(language, metric)`'s corpus distribution supports a rank at `cut`.

False when a single occurrence already lands at or above the cut, which is the signature of
a metric that is zero for most units. Such a metric is read on its absolute band alone.
"""
function percentile_informs(baseline::Baseline, language::Symbol, metric::Symbol, cut::Real)
    at_one = percentile(baseline, language, metric, 1)
    return at_one === nothing || at_one < cut
end

"""
    percentile_guard(baseline, rules, cut) -> Dict{Tuple{Symbol, Symbol}, Bool}

Whether each `(language, metric)` the baseline sampled supports a rank, resolved once per
scan. Read per unit, so computing it per unit would repeat one binary search across every
function in the corpus.
"""
function percentile_guard(baseline::Baseline, cut::Real)
    out = Dict{Tuple{Symbol, Symbol}, Bool}()
    for (language, metric) in keys(baseline.samples)
        out[(language, metric)] = percentile_informs(baseline, language, metric, cut)
    end
    return out
end
