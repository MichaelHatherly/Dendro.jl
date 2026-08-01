# How a corpus-relational pass turns a measured value into findings. Every such pass
# reads the same two scores, a fixed band and a corpus percentile, and emits on the same
# rule, so that reading lives here rather than in the file that defines what a `Finding`
# is and how one renders.

# The two scores one value carries: its severity against the fixed `band`, and its
# percentile among `counts`, the values of everything scored alongside it. The percentile
# is `nothing` unless `enough` of them were scored to rank against, so a thin corpus is
# read on the absolute band alone. Every corpus-relational pass reads a value this way,
# whatever it scores, a file, a directory pair, or a cycle.
function two_scores(value::Int, counts::Vector{Int}, band::Tuple{Int, Int}, enough::Bool)
    absolute = severity(value, band)
    pct = enough ? searchsortedlast(counts, value) / length(counts) : nothing
    return absolute, pct
end

# Whether a reading is reported: either score trips, the absolute band or the corpus rank.
# Both halves are kept, since absolute alone misses an outlier in a uniformly weak corpus
# and the rank alone calls that corpus fine.
fires(absolute::Symbol, pct::Union{Float64, Nothing}, cut::Real) =
    absolute !== :ok || (pct !== nothing && pct >= cut)

"""
    scored_findings(metric, scored, band, cut, min_files; min_reported=1) -> Vector{Finding}

One `metric` finding per entry of `scored`, the emission the file-level corpus passes
share. Each entry pairs a file with its value and the locations to report it at, the
first of which is the site a `dendro-ignore` covers. A finding is emitted when the value
breaches the absolute `band` or lands at or above the `cut` percentile of the scored
values, the two-score model; the percentile is read only once the corpus holds
`min_files` scored entries, and is `nothing` below that.

`min_reported` is the smallest value that names something to act on. Entries below it
stay in the scored population, so they count toward the percentile of the entries above,
but never emit. Findings come back sorted by descending value, then file and line.

An entry is keyed by its `ParsedFile` because the suppression directive is read off it, and
that is what bounds this to the passes scoring a file. A pass scoring something else reads
its directives out of a path-keyed dict instead: [`directory_findings`](@ref) is that shape
for the two passes whose subject is a directory. `:misplaced` scores a unit, `:back_edge` a
directory pair, `:dependency_cycle` a cyclic component, and `:hub` a graph node, and those
four build their locations only for the entries that fire, which neither shape can express
because both take them upfront. They emit directly and share the part that is genuinely
common, the band-and-percentile reading through `two_scores` and `fires`.
"""
function scored_findings(
        metric::Symbol, scored::Vector{Tuple{ParsedFile, Int, Vector{Location}}},
        band::Tuple{Int, Int}, cut::Real, min_files::Integer; min_reported::Int = 1
    )
    findings = Finding[]
    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, value, locations) in scored
        value >= min_reported || continue
        absolute, pct = two_scores(value, counts, band, enough)
        fires(absolute, pct, cut) || continue
        sup = is_suppressed(f.directives, locations[1].line, metric)
        push!(findings, Finding(metric, locations, value, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end

"""
    directory_findings(metric, scored, directives, band, cut, enough) -> Vector{Finding}

One `metric` finding per entry of `scored`, the emission the two directory passes share.
Each entry pairs a directory's value with the locations to report it at, the first of which
stands for the directory itself and is the site a `dendro-ignore` covers. A finding is
emitted when the value breaches the absolute `band` or lands at or above the `cut`
percentile of the scored values, the two-score model; `enough` says whether the corpus holds
enough scored directories for that rank to mean anything, and each pass decides it against
its own floor. Findings come back sorted by descending value, then file and line.

A directory is not a `ParsedFile`, so the suppression directives arrive as `directives`,
keyed by path, which is what separates this from [`scored_findings`](@ref). Both take their
locations upfront, which is what keeps the passes building locations lazily out of either.
"""
function directory_findings(
        metric::Symbol, scored::Vector{Tuple{Int, Vector{Location}}},
        directives::Dict{String, Vector{Directive}},
        band::Tuple{Int, Int}, cut::Real, enough::Bool
    )
    findings = Finding[]
    counts = sort([value for (value, _) in scored])
    for (value, locations) in scored
        absolute, pct = two_scores(value, counts, band, enough)
        fires(absolute, pct, cut) || continue
        anchor = first(locations)
        sup = is_suppressed(get(() -> Directive[], directives, anchor.file), anchor.line, metric)
        push!(findings, Finding(metric, locations, value, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
