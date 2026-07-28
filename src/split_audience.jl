# A file whose definitions serve two or more audiences that never meet. The outward dual
# of within-file cohesion: `:low_cohesion` reads inward and splits a file by the bindings
# its own units share, this reads outward and splits it by the files that consume its
# definitions. The two are independent. A file can share helpers throughout, so it reads
# as cohesive, while serving two groups of consumers whose reference sets never overlap;
# it can also be internally fragmented while serving one audience.
#
# The audience is read from resolved references, never from declared exports. A language
# with no export marker exposes every top-level name, so an export-counting reading would
# collapse to "this file is big" for Python, Go, and C. References work in every language
# because they are what the corpus already resolves. Where a language declares exports
# they refine which definitions a consumer can see, through the same visibility gate the
# rest of placement reads, but they never decide the finding.
#
# Name-based and lexical throughout, like the rest of placement: a consumer is a file
# holding a reference that resolves to a definition here by name, never by type or
# dispatch.

# Absolute band on the number of audience groups a file serves. One group is a file with
# a single audience, the ordinary case. No external standard sets this, so it sits above
# the spread of an idiomatic corpus. Measured over 294 scored files across Dendro,
# DataFrames.jl, HTTP.jl, Makie, flask, requests, fastmcp, markitdown, ripgrep, and Guava,
# 85% serve one audience, 10% serve two, 5% serve three, and two files in the whole
# measurement served more, the widest at five. So 3 marks a file that has separated into
# distinct interfaces and 5 one that has done it repeatedly, which leaves the `:high` floor
# satisfiable: one file in the measurement reaches it and nine of the ten corpora carry
# none. A value of 2 is splittable but too common to flag on its own, so the percentile
# half carries it, firing where two audiences are unusual for the corpus and staying quiet
# where they are not.
const SPLIT_AUDIENCE_BAND = (3, 5)

# An audience group needs this many definitions before it reads as an interface rather
# than a helper with a caller. One definition used by one other file is ordinary. Shared
# with `:hub`, which proposes a split along the same groups.
const MIN_AUDIENCE_DEFS = 2

# A file consumed by fewer than this many other files has one audience by construction,
# so it has nothing to split along and stays out of the scored population, the same way
# the back-edge grain is only read between directories that reference each other at all.
# The floor is on the file's whole audience, not on one group's: a group of definitions
# devoted to a single consumer is a real interface, and the canonical split is two of
# them. `:hub` reads its own floor per group, since it names the groups as a proposal
# rather than counting them as a score.
const MIN_SPLIT_CONSUMERS = 2

# A file with fewer units than this is too small to read as serving separate audiences.
const MIN_AUDIENCE_UNITS = 3

# The fewest audiences that name a split. One audience is the metric's own reading of a
# file with nothing to separate, so it is never reported, however unusual it is for the
# corpus. Such a file still counts toward the distribution: it is the population two
# audiences are unusual against.
const MIN_SPLIT_GROUPS = 2

# The corpus needs this many scored files before the group-count percentile means
# anything; under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_AUDIENCE_FILES = 5

# For each file in `targets`, the definitions in it that something else references and the
# set of files referencing each. The audience a definition serves is who names it, so this
# reads the same resolved references the graphs are built from; a file's own definitions
# are outside its visibility map, so every reference here crosses a file boundary. A
# reference matching several visible definitions counts toward each: the match is by name,
# and picking one would need the dispatch resolution this never does. A reference in
# top-level code counts like any other, since the question is which file consumes the
# definition, not which unit.
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

# The audience groups among one file's consumed definitions, `defs` mapping each to the
# files that reference it. Two definitions belong to the same audience when a consumer
# reaches both, so the groups are the connected components of that projection, found with
# the same flood fill cohesion reads. A group below `MIN_AUDIENCE_DEFS` definitions or
# `min_consumers` consumers is dropped: a definition or two that one file happens to use is
# not a seam to cut along.
#
# The definitions are line-ordered before the projection is built, so a component's
# earliest line is its smallest position and the flood fill seeds components in that order:
# the groups come out earliest line first, each already led by its own earliest definition,
# with no second sort. Each group is a vector of definition indices into `table.defs`.
function audience_components(
        defs::Dict{Int, Set{String}}, table::SymbolTable; min_consumers::Int = 1
    )
    dis = sort!(collect(keys(defs)); by = di -> (table.defs[di].line, table.defs[di].name, di))
    by_consumer = Dict{String, Vector{Int}}()
    for (i, di) in enumerate(dis)
        for consumer in sort!(collect(defs[di]))
            push!(get!(() -> Int[], by_consumer, consumer), i)
        end
    end
    # Star-link each consumer's definitions to the first of them, as the within-file
    # binding edges do: the components are the same and the edge count stays linear.
    adj = [Dict{Int, Float64}() for _ in eachindex(dis)]
    for consumer in sort!(collect(keys(by_consumer)))
        members = by_consumer[consumer]
        base = first(members)
        for m in members
            m == base && continue
            adj[base][m] = 1.0
            adj[m][base] = 1.0
        end
    end
    groups = Vector{Int}[]
    for group in components(adj, collect(eachindex(dis)))
        length(group) < MIN_AUDIENCE_DEFS && continue
        consumers = Set{String}()
        for i in group
            union!(consumers, defs[dis[i]])
        end
        length(consumers) < min_consumers && continue
        push!(groups, Int[dis[i] for i in sort!(group)])
    end
    return groups
end

"""
    cluster_split_audience(files, table; band=$SPLIT_AUDIENCE_BAND, cut=0.95, min_files=$MIN_AUDIENCE_FILES, visible=corpus_visibility(files, table)) -> Vector{Finding}

Files serving several disjoint audiences, reported as `:split_audience`. For each
definition something outside its file references, the consumer files are collected from
[`corpus_references`](@ref); two definitions are linked when their consumer sets meet, and
the connected components of that projection are the file's audiences. The score is the
count of groups holding at least `$MIN_AUDIENCE_DEFS` definitions, so a helper with one
caller is not an audience. Each finding carries both scores, the absolute `band` on that
count and the corpus percentile, fired when either trips. The locations are one
representative definition per group, earliest line first, the split the finding proposes.

A file serving one audience has nothing to separate, so it is never reported, whatever
the corpus distribution says. It stays in the scored population, since it is what makes
two audiences unusual or ordinary for a corpus.

A file with fewer than `$MIN_AUDIENCE_UNITS` units is too small to read this way, and a
file fewer than `$MIN_SPLIT_CONSUMERS` other files consume has one audience by
construction and is left out of the scored population entirely, so the percentile compares
only files that could split.

The audience is resolved from references, not from declared exports: `file_exports`
returns nothing for a language with no export marker, where an export reading would
degenerate into file size. Where a language does declare exports they gate what a consumer
can see, through the same visibility map the rest of placement reads.

Pass a prebuilt `visible` from [`corpus_visibility`](@ref) to share one resolution with a
caller that has already resolved the corpus.

Failure modes: a genuine multi-purpose utility module serves several audiences by design
and is answered with a suppression, not a smarter model. A file that `:hub` also flags is
expected to carry both findings, which say different things and propose the same edit from
two directions.
"""
function cluster_split_audience(
        files::Vector{ParsedFile}, table::SymbolTable;
        band::Tuple{Int, Int} = SPLIT_AUDIENCE_BAND, cut::Real = 0.95,
        min_files::Integer = MIN_AUDIENCE_FILES,
        visible::Dict{String, Dict{String, Vector{Int}}} = corpus_visibility(files, table)
    )
    consumed = consumer_sets(files, table, visible, Set{String}(f.file for f in files))

    scored = Tuple{ParsedFile, Int, Vector{Location}}[]
    for f in files
        length(functions(f.index)) < MIN_AUDIENCE_UNITS && continue
        defs = get(() -> Dict{Int, Set{String}}(), consumed, f.file)
        audience = Set{String}()
        for consumers in values(defs)
            union!(audience, consumers)
        end
        length(audience) < MIN_SPLIT_CONSUMERS && continue
        groups = audience_components(defs, table)
        isempty(groups) && continue
        locations = Location[
            Location(f.file, table.defs[first(g)].line, table.defs[first(g)].name) for g in groups
        ]
        push!(scored, (f, length(locations), locations))
    end
    return scored_findings(
        RELATIONAL.split_audience, scored, band, cut, min_files;
        min_reported = MIN_SPLIT_GROUPS
    )
end
