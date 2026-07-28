# The Crossing anti-pattern, read off the file graph. A file that both depends on much of
# the corpus and is depended on by much of it propagates every change in either direction,
# and it carries the highest measured defect density of any structural position. Fan-in
# alone is every utility module and fan-out alone every orchestrator, neither of which is a
# smell, so the conjunction is the whole signal and `min(fan_in, fan_out)` is the whole
# score. Distinct file counts, matching Arcan's FanIn/FanOut, not reference counts: a file
# reached a hundred times from one place is not a crossing.
#
# The proposal is the split. A hub whose definitions serve two audiences that share no
# consumer is one bounded edit, so the finding names a representative definition per
# audience. A hub whose consumers all reach the whole file has no such edit, and the
# finding says so by carrying the file alone rather than dressing a single group up as a
# proposal. Name-based and lexical like the rest of the graph layer: a consumer set is who
# references the name, never who dispatches to it.

# Absolute band on `min(fan_in, fan_out)`, the count of files a hub both depends on and is
# depended on by.
#
# Measured over ten corpora with a resolvable file graph, Julia, Python and Rust, from 17
# to 145 files. The crossing count has no corpus-independent scale: its p90 is 2 in
# ripgrep's crates, 3 in Pkg.jl, 6 in Dendro's own src and in Flask, 10 in DataFrames.jl
# and JuliaSyntax.jl, 12 in HTTP.jl and 25 in Makie, and the largest crossing anywhere runs
# from 2 to 53. So the band can only mark the level at which a crossing reads as central
# whatever the corpus, and the rank against the corpus's own crossings does the separating.
# `warn` at 15 sits above the p90 of every corpus measured but Makie, firing on the files a
# reader would name unprompted: HTTP.jl's client at 17, DataFrames' `AbstractDataFrame` at
# 15. `high` at 30 enters the error floor every dogfooding package gates on, so it marks a
# file that is central beyond argument: it fires on 5 of Makie's 145 files and on nothing
# else measured. At (8, 15) that same corpus reports 33 files at `:high`, a gate nobody can
# satisfy.
const HUB_BAND = (15, 30)

# What a group of definitions has to hold to read as an audience worth splitting off: this
# many definitions, reaching this many consumer files between them. One definition used by
# one file is ordinary rather than a seam, and a proposal built from singletons would name
# every definition its own audience.
const MIN_AUDIENCE_DEFS = 2
const MIN_AUDIENCE_CONSUMERS = 2

# The corpus needs this many files before a crossing count means anything. Below it every
# file touches most of the others, so `min(fan_in, fan_out)` reads corpus shape rather than
# architecture, in the same spirit as `MIN_COHESION_FILES`. Unlike that floor this one
# gates the whole rule, not just its percentile: the absolute band is as size-dependent as
# the rank here.
const MIN_HUB_CORPUS_FILES = 20

"""
    cluster_hub(files, fg, table; visible=corpus_visibility(files, table), band=$HUB_BAND, cut=0.95, min_files=$MIN_HUB_CORPUS_FILES) -> Vector{Finding}

Files that both depend on much of the corpus and are depended on by much of it, reported
as `:hub`. The score is `min(fan_in, fan_out)` over the distinct files an edge of `fg`
joins: a utility at 50 in and 1 out scores 1, an orchestrator at 1 in and 30 out scores 1,
and a file at 20 in and 15 out scores 15. Nothing else enters the score, because nothing
else is the anti-pattern.

Both scores fire it, the absolute `band` and the corpus percentile, and the percentile
does most of the work. Fan-in and fan-out both scale with corpus size, so a fixed band is
weaker here than for any per-function metric: it can only mark the level at which a
crossing is worth reading whatever the corpus, and the rank against the corpus's own
crossing files is what places one file against another. The ranked population is the files
that cross at all, those with an edge in each direction, since a file that is pure utility
or pure orchestration has no crossing to rank. A corpus below `min_files` is not scored.

The first location is the hub file at its first unit, carrying no unit name: the finding is
about the file, not one function in it. When the hub's externally-referenced
definitions fall into two or more audiences, groups of definitions linked by sharing a
consumer file, one representative definition per audience follows, earliest line first:
that split is the proposed edit. A group is an audience only above `MIN_AUDIENCE_DEFS`
definitions and `MIN_AUDIENCE_CONSUMERS` consumers, since one definition one file happens
to use is not a seam. A hub left with fewer than two audiences carries the file alone, a
warning with no proposal rather than a proposal that does not hold.

That makes the location set depend on who consumes the file, which the gate ratchet reads:
`fkey` is the metric paired with every location, so a change that merges or splits an
audience rewrites the key and the ratchet reports the hub as new. This is the same trade
`:back_edge` makes, and for the same reason. A consumer change that reshapes a hub's
audiences has changed what the finding proposes, and a gate that stayed quiet through it
would be reporting a stale edit.

Consumer sets are resolved only for the files that fire, so a corpus with no hub pays
nothing for the split proposal.
"""
function cluster_hub(
        files::Vector{ParsedFile}, fg::FileGraph, table::SymbolTable;
        visible::Dict{String, Dict{String, Vector{Int}}} = corpus_visibility(files, table),
        band::Tuple{Int, Int} = HUB_BAND, cut::Real = 0.95,
        min_files::Integer = MIN_HUB_CORPUS_FILES
    )
    findings = Finding[]
    length(fg.files) < min_files && return findings
    scored = crossing_scores(fg)
    isempty(scored) && return findings

    counts = sort([value for (_, value) in scored])
    # A rank needs a population. With fewer crossing files than the corpus floor asks of a
    # corpus, the percentile ranks a handful of files against each other and says nothing,
    # so only the absolute band fires, as cohesion does on a thin corpus.
    enough = length(scored) >= min_files
    hits = Tuple{Int, Int, Symbol, Union{Float64, Nothing}}[]
    for (node, value) in scored
        absolute = severity(value, band)
        pct = enough ? searchsortedlast(counts, value) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        push!(hits, (node, value, absolute, pct))
    end
    isempty(hits) && return findings

    byfile = Dict{String, ParsedFile}(f.file => f for f in files)
    audiences = consumer_sets(files, table, visible, Set{String}(fg.files[node] for (node, _, _, _) in hits))
    for (node, value, absolute, pct) in hits
        path = fg.files[node]
        anchor = Location(path, fg.first_line[node], "")
        locations = [anchor]
        reps = audience_reps(get(() -> Dict{Int, Set{String}}(), audiences, path), table)
        length(reps) > 1 &&
            append!(locations, [Location(path, table.defs[di].line, table.defs[di].name) for di in reps])
        sup = is_suppressed(byfile[path].directives, anchor.line, RELATIONAL.hub)
        push!(findings, Finding(RELATIONAL.hub, locations, value, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end

# Per file that crosses at all, its `(node, min(fan_in, fan_out))`, in node order. A file
# with no edge in one direction is not a crossing and is left out of the scored population
# entirely, so it neither fires nor sits in the denominator the rank is read against.
function crossing_scores(fg::FileGraph)
    n = length(fg.files)
    fan_in = zeros(Int, n)
    fan_out = zeros(Int, n)
    for (src, dst) in keys(fg.edges)
        fan_out[src] += 1
        fan_in[dst] += 1
    end
    scored = Tuple{Int, Int}[]
    for node in 1:n
        value = min(fan_in[node], fan_out[node])
        value > 0 && push!(scored, (node, value))
    end
    return scored
end

# For each file in `targets`, the definitions in it that something else references and the
# set of files referencing each. The audience a definition serves is who names it, so this
# reads the same resolved references the file graph is built from; a file's own definitions
# are outside its visibility map, so every reference here crosses a file boundary.
function consumer_sets(
        files::Vector{ParsedFile}, table::SymbolTable,
        visible::Dict{String, Dict{String, Vector{Int}}}, targets::Set{String}
    )
    out = Dict{String, Dict{Int, Set{String}}}()
    for (f, _, candidates) in corpus_references(files, visible)
        for di in candidates
            d = table.defs[di]
            d.file in targets || continue
            defs = get!(() -> Dict{Int, Set{String}}(), out, d.file)
            push!(get!(() -> Set{String}(), defs, di), f.file)
        end
    end
    return out
end

# One representative definition per audience group, earliest line first. Two definitions
# belong to the same audience when a consumer file reaches both, so the groups are the
# connected components of that projection, found with the same flood fill cohesion reads.
# A group below `MIN_AUDIENCE_DEFS` or `MIN_AUDIENCE_CONSUMERS` is dropped rather than
# named: a definition or two that one file happens to use is not a seam to cut along.
# The definitions are line-ordered before the projection is built, so a component's earliest
# line is its smallest position, and the flood fill seeds components in that order: the
# representatives come out earliest line first without a second sort.
function audience_reps(defs::Dict{Int, Set{String}}, table::SymbolTable)
    dis = sort!(collect(keys(defs)); by = di -> (table.defs[di].line, table.defs[di].name, di))
    adj = [Dict{Int, Float64}() for _ in eachindex(dis)]
    byconsumer = Dict{String, Vector{Int}}()
    for (i, di) in enumerate(dis)
        for consumer in sort!(collect(defs[di]))
            push!(get!(() -> Int[], byconsumer, consumer), i)
        end
    end
    # Star-link each consumer's definitions to the first of them, as the within-file
    # binding edges do: the components are the same and the edge count stays linear.
    for consumer in sort!(collect(keys(byconsumer)))
        members = byconsumer[consumer]
        base = first(members)
        for m in members
            m == base && continue
            adj[base][m] = 1.0
            adj[m][base] = 1.0
        end
    end
    reps = Int[]
    for group in components(adj, collect(eachindex(dis)))
        length(group) < MIN_AUDIENCE_DEFS && continue
        consumers = Set{String}()
        for i in group
            union!(consumers, defs[dis[i]])
        end
        length(consumers) < MIN_AUDIENCE_CONSUMERS && continue
        push!(reps, dis[minimum(group)])
    end
    return reps
end
