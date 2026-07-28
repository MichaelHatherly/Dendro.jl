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
# the spread of an idiomatic corpus. Measured over 291 scored files across Dendro,
# DataFrames.jl, HTTP.jl, Makie, flask, requests, fastmcp, markitdown, ripgrep, and Guava,
# 85% serve one audience, 10% serve two, 4% serve three, and two files in the whole
# measurement served more. So 3 marks a file that has separated into distinct interfaces
# and 5 one that has done it repeatedly, which leaves the `:high` floor satisfiable: no
# corpus measured carried more than one such file, and most carried none. A value of 2 is
# splittable but too common to flag on its own, so the percentile half carries it, firing
# where two audiences are unusual for the corpus and staying quiet where they are not.
const SPLIT_AUDIENCE_BAND = (3, 5)

# An audience group needs this many definitions before it reads as an interface rather
# than a helper with a caller. One definition used by one other file is ordinary.
const MIN_AUDIENCE_DEFS = 2

# A file consumed by fewer than this many other files has one audience by construction,
# so it has nothing to split along and stays out of the scored population, the same way
# the back-edge grain is only read between directories that reference each other at all.
# The floor is on the file's whole audience, not on one group's: a group of definitions
# devoted to a single consumer is a real interface, and the canonical split is two of
# them.
const MIN_AUDIENCE_CONSUMERS = 2

# A file with fewer units than this is too small to read as serving separate audiences.
const MIN_AUDIENCE_UNITS = 3

# The corpus needs this many scored files before the group-count percentile means
# anything; under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_AUDIENCE_FILES = 5

# The ordering a group's representative and a file's locations follow: earliest line
# first, ties broken by name so the choice does not depend on the order the symbol table
# happened to be built in.
rep_key(d::CorpusDef) = (d.line, d.name)

# Per definition referenced from outside its own file, the set of files that reference it.
# A reference matching several visible definitions counts toward each: the match is by
# name, and picking one would need the dispatch resolution this never does. A reference in
# top-level code counts like any other, since the question is which file consumes the
# definition, not which unit.
function consumer_files(
        files::Vector{ParsedFile}, table::SymbolTable,
        visible::Dict{String, Dict{String, Vector{Int}}}
    )
    consumers = Dict{Int, Set{String}}()
    for (f, _, candidates) in corpus_references(files, visible)
        for di in candidates
            table.defs[di].file == f.file && continue
            push!(get!(() -> Set{String}(), consumers, di), f.file)
        end
    end
    return consumers
end

# The audience groups among `defs`, the consumed definitions of one file: the connected
# components of the graph linking two definitions whose consumer sets meet. Each consumer
# file's definitions are star-linked to the first of them, which forms the same components
# as linking every pair and stays linear in the consumption edges. A group is a vector of
# indices into `defs`.
function audience_groups(defs::Vector{Int}, consumers::Dict{Int, Set{String}})
    by_consumer = Dict{String, Vector{Int}}()
    for (i, di) in enumerate(defs)
        for file in sort!(collect(consumers[di]))
            push!(get!(() -> Int[], by_consumer, file), i)
        end
    end
    adj = [Dict{Int, Float64}() for _ in defs]
    for file in sort!(collect(keys(by_consumer)))
        members = by_consumer[file]
        base = first(members)
        for m in members
            m == base && continue
            adj[base][m] = 1.0
            adj[m][base] = 1.0
        end
    end
    return components(adj, collect(eachindex(defs)))
end

# The definition an audience group is reported at: its earliest line.
function audience_rep(table::SymbolTable, defs::Vector{Int}, group::Vector{Int})
    rep = defs[first(group)]
    for i in group
        di = defs[i]
        rep_key(table.defs[di]) < rep_key(table.defs[rep]) && (rep = di)
    end
    return rep
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

A file with fewer than `$MIN_AUDIENCE_UNITS` units is too small to read this way, and a
file fewer than `$MIN_AUDIENCE_CONSUMERS` other files consume has one audience by
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
    findings = Finding[]
    consumers = consumer_files(files, table, visible)
    consumed = Dict{String, Vector{Int}}()
    for di in sort!(collect(keys(consumers)))
        push!(get!(() -> Int[], consumed, table.defs[di].file), di)
    end

    scored = Tuple{ParsedFile, Int, Vector{Location}}[]
    for f in files
        length(functions(f.index)) < MIN_AUDIENCE_UNITS && continue
        defs = get(consumed, f.file, Int[])
        audience = Set{String}()
        for di in defs
            union!(audience, consumers[di])
        end
        length(audience) < MIN_AUDIENCE_CONSUMERS && continue
        groups = audience_groups(defs, consumers)
        reps = Int[audience_rep(table, defs, g) for g in groups if length(g) >= MIN_AUDIENCE_DEFS]
        isempty(reps) && continue
        sort!(reps; by = di -> rep_key(table.defs[di]))
        locations = Location[Location(f.file, table.defs[di].line, table.defs[di].name) for di in reps]
        push!(scored, (f, length(locations), locations))
    end
    isempty(scored) && return findings

    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, count, locations) in scored
        absolute = severity(count, band)
        pct = enough ? searchsortedlast(counts, count) / length(counts) : nothing
        (absolute != :ok || (pct !== nothing && pct >= cut)) || continue
        sup = is_suppressed(f.directives, locations[1].line, RELATIONAL.split_audience)
        push!(findings, Finding(RELATIONAL.split_audience, locations, count, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
