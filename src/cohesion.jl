# Within-file cohesion. A file's functions form a graph: two are linked when they
# reference a common file-local binding, a helper, type, or constant defined in the
# same file, read from the lexical bindings `bindings.jl` resolves. A file that breaks
# into several disconnected components holds that many independent concerns, the LCOM4
# reading of low cohesion. The signal stays syntactic and within one file, linking on
# a resolved binding, never a symbol across files. Scored like naturalness: an absolute
# band on the component count and the corpus percentile, fired when either trips.

# Absolute band on the number of components in a file. One component is a cohesive
# file; the band marks where the count of independent concerns is worth a look. No
# external standard sets it, so it sits above an idiomatic corpus's spread, our own
# included, the level at which a file holds enough disconnected concerns to read
# regardless of the corpus. The percentile carries the corpus-relative signal.
const LOW_COHESION_BAND = (4, 6)

# A file with fewer units than this is too small to read as disorganised.
const MIN_COHESION_UNITS = 2

# The corpus needs this many scored files before its component-count percentile means
# anything; under it only the absolute band fires, as naturalness does on a thin corpus.
const MIN_COHESION_FILES = 5

# A binding referenced by more than this fraction of a file's units is cross-cutting,
# a file-local utility every concern reaches for, and links nothing: keeping its edges
# would fold genuine concerns into one. Binding resolution already drops the imported
# and global names a string graph trips on, so the default keeps every file-local
# binding (1.0 never drops) and dogfood tunes it down only if needed.
const COHESION_UBIQUITY = 1.0

# The innermost function unit whose byte span contains `[from, to]`, or 0 when the
# position lies in no function (top-level code). Units are few per file, so a scan.
function containing_unit(ranges::Vector{Tuple{Int, Int}}, from::Int, to::Int)
    best = 0
    best_span = typemax(Int)
    for (i, r) in enumerate(ranges)
        (r[1] <= from && to <= r[2]) || continue
        span = r[2] - r[1]
        span < best_span || continue
        best = i
        best_span = span
    end
    return best
end

# The within-file links a file's bindings imply: each entry lists the local unit indices
# that share one definition, the units referencing it plus, when it lives in a unit, its
# owner. A binding referenced by more than `ubiquity` of the units links nothing, a
# cross-cutting utility rather than a shared concern. The connectivity `:low_cohesion`
# reads as components and `:scattered` folds into the corpus graph.
function binding_groups(index::QueryIndex, ubiquity::Float64)
    units = functions(index)
    n = length(units)
    ranges = Tuple{Int, Int}[TreeSitter.byte_range(u.node) for u in units]
    # Units referencing one definition, keyed by the definition's identity.
    groups = Dict{NodeId, Vector{Int}}()
    for (refid, defid) in index.bindings
        ui = containing_unit(ranges, refid[1], refid[2])
        ui == 0 && continue
        push!(get!(() -> Int[], groups, defid), ui)
    end
    out = Vector{Int}[]
    threshold = ubiquity * n
    for (defid, members) in groups
        length(unique(members)) > threshold && continue
        owner = containing_unit(ranges, defid[1], defid[2])
        push!(out, owner == 0 ? members : push!(copy(members), owner))
    end
    return out
end

"""
    file_components(index, ubiquity=$COHESION_UBIQUITY) -> Union{Tuple{Int, Vector{Int}}, Nothing}

The connected-component count of a file's function units and a representative unit
index per component (earliest line first), or `nothing` when the file has fewer than
`$MIN_COHESION_UNITS` units. Two units are linked when one references a binding the
other defines or references, by the resolved `index.bindings`. A binding referenced
by more than `ubiquity` of the units links nothing, a cross-cutting utility rather
than a shared concern.
"""
function file_components(index::QueryIndex, ubiquity::Float64 = COHESION_UBIQUITY)
    units = functions(index)
    n = length(units)
    n < MIN_COHESION_UNITS && return nothing
    parent = collect(1:n)
    for members in binding_groups(index, ubiquity)
        base = members[1]
        for m in members
            parent[uf_find(parent, m)] = uf_find(parent, base)
        end
    end
    rep = Dict{Int, Int}()
    for i in 1:n
        root = uf_find(parent, i)
        cur = get(rep, root, 0)
        (cur == 0 || units[i].firstline < units[cur].firstline) && (rep[root] = i)
    end
    reps = sort!(collect(values(rep)); by = i -> units[i].firstline)
    return (length(reps), reps)
end

"""
    cluster_low_cohesion(files; band=$LOW_COHESION_BAND, cut=0.95, min_files=$MIN_COHESION_FILES) -> Vector{Finding}

Files whose functions split into several independent components, reported as
`:low_cohesion`. Each carries both scores: the absolute `band` on the component
count and the corpus percentile, fired when either trips. The finding's locations
are one representative function per component. A language with no scopes query is
skipped, its functions carrying no bindings to link.
"""
function cluster_low_cohesion(
        files::Vector{ParsedFile}; band::Tuple{Int, Int} = LOW_COHESION_BAND,
        cut::Real = 0.95, min_files::Integer = MIN_COHESION_FILES, ubiquity::Float64 = COHESION_UBIQUITY
    )
    findings = Finding[]
    scored = Tuple{ParsedFile, Int, Vector{Int}}[]
    for f in files
        scopes_query_for(f.language) === nothing && continue
        fc = file_components(f.index, ubiquity)
        fc === nothing && continue
        push!(scored, (f, fc[1], fc[2]))
    end
    isempty(scored) && return findings
    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, components, reps) in scored
        absolute = severity(components, band)
        pct = enough ? searchsortedlast(counts, components) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        units = functions(f.index)
        locations = [Location(f.file, units[i].firstline, unit_name(units[i], f.index)) for i in reps]
        sup = is_suppressed(f.directives, units[reps[1]].firstline, RELATIONAL.low_cohesion)
        push!(findings, Finding(RELATIONAL.low_cohesion, locations, components, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value), first(f.locations).file, first(f.locations).line))
    return findings
end
