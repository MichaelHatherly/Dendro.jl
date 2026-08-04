# Is a definition near what uses it. `:misplaced` asks whether a unit is in the right
# file; this asks whether it is in the right place inside one. A definition sitting
# several other definitions away from the nearest code that names it costs a reader a
# scroll and a search on every visit, and the edit it names is one definition moved beside
# one use.
#
# The score is how many top-level definitions lie between the definition and the nearest
# unit referencing it, so a definition next to a use scores zero. Nearest rather than mean
# or median, and that choice is what keeps the rule quiet on a file-wide helper without a
# ubiquity cut: a name most of the file reaches for has a use close by wherever it sits,
# so it scores low on its own. A median would score it by the distance to the middle of
# the file and report every such helper. What survives is a definition whose uses all sit
# together somewhere else, which is the case with a home to move to.
#
# Distance is counted in definitions rather than lines. A reader crossing one 200-line
# function has crossed one thing, and `function_length` is the rule that reads the 200.
#
# Name-based and lexical like the rest of placement, and within one file: the references
# come from `index.bindings`, the definitions from the corpus symbol table, and neither
# side resolves a type or a dispatch.
#
# Off by default, and the band comment says why: the level a review comment is written at
# is the level ordinary declaration order sits at, so the rule reports a proposal rather
# than a measurement. A project turns it on with `[rules] distant_definition = true` and
# sets the band to the convention it keeps.

# Absolute band on the count of definitions between a definition and its nearest use.
#
# Measured over 5798 scored definitions in nine corpora across five languages: this
# package, DataFrames.jl, HTTP.jl, CommonMark.jl, flask, requests, fastmcp, ripgrep and
# guava. Separation is ordinary. Half of all scored definitions sit within one definition
# of a use, but the tail is long: the pooled p90 is 15, the p95 28, the p99 74, and the
# per-corpus p95 runs from 12 to 44. So `warn` at 25 sits above the p95 of seven of the
# nine, and `high` at 50 above the p99 of seven, the shape `:scattered` and `:hub` take.
#
# The band cannot go lower and the measurement is what says so. Hand reading of every
# definition this package separates by 4 to 15 found ordinary declaration order
# throughout, a helper or a documented constant written above the one function that reads
# it, and at those levels the rule reports a tenth of a corpus's definitions. Nothing
# syntactic separates a helper hoisted for reading order from one stranded by an edit, so
# what is left to read is the size of the gap. A project whose convention is to define
# beside the use retunes `[bands] distant_definition` down to it, which is the layer the
# opinion belongs in.
const DISTANT_DEFINITION_BAND = (25, 50)

# The corpus needs this many scored definitions before the gap percentile means anything;
# under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_DISTANT_DEFINITION_DEFS = 5

# Each unit's place in the file's sequence of top-level units, in `units(index)` order: a
# top-level unit takes the next place and a unit nested in one takes its parent's. A file's
# units include the nested short-form definitions, so counting raw indices would read a
# helper defined inside a function as one more thing between two top-level definitions,
# which is not what a reader scrolls past.
function toplevel_ordinals(index::QueryIndex)
    spans = unit_ranges(index)
    ordinals = zeros(Int, length(spans))
    place, enclosing_to = 0, 0
    # Pre-order, so a unit opens before anything nested in it and `enclosing_to` is the end
    # of the top-level unit currently open.
    for i in sortperm(spans; by = s -> (s[1], -s[2]))
        from, to = spans[i]
        if from > enclosing_to
            place += 1
            enclosing_to = to
        end
        ordinals[i] = place
    end
    return ordinals
end

# The nearest use of each of one file's top-level definitions: per definition index in
# `table.defs`, the count of definitions between it and the closest unit naming it, paired
# with that unit. A reference sharing its definition's top-level unit is not a use of it
# from elsewhere and measures no distance. Ties go to the earlier unit, so the result does
# not depend on the order the binding map iterates in.
function nearest_uses(f::ParsedFile, byid::Dict{Tuple{String, NodeId}, Int})
    gaps = Dict{Int, Int}()
    users = Dict{Int, Int}()
    ordinals = toplevel_ordinals(f.index)
    ranges = unit_ranges(f.index)
    for (refid, defid) in f.index.bindings
        di = get(byid, (f.file, defid), 0)
        di == 0 && continue
        du = containing_unit(ranges, defid[1], defid[2])
        ru = containing_unit(ranges, refid[1], refid[2])
        (du == 0 || ru == 0) && continue
        gap = abs(ordinals[ru] - ordinals[du]) - 1
        gap < 0 && continue
        best = get(gaps, di, typemax(Int))
        (gap < best || (gap == best && ru < users[di])) || continue
        gaps[di] = gap
        users[di] = ru
    end
    return gaps, users
end

"""
    cluster_distant_definition(files, table; band=$DISTANT_DEFINITION_BAND, cut=0.95, min_defs=$MIN_DISTANT_DEFINITION_DEFS) -> Vector{Finding}

Definitions separated from the code that uses them, reported as `:distant_definition`. The
score is the number of top-level definitions lying between a definition and the nearest
unit in its file that references it, so a definition beside a use scores zero and never
reports. Each finding carries the absolute `band` on that count and the corpus percentile
over every scored definition, fired when either trips. The first location is the
definition, the second the use nearest it.

Within one file and name-based: the references are the lexical bindings
[`resolve_bindings!`](@ref) resolved, the definitions the top-level symbols `table` holds,
and a language with no scopes query is skipped, its files carrying no bindings to read.
"""
function cluster_distant_definition(
        files::Vector{ParsedFile}, table::SymbolTable;
        band::Tuple{Int, Int} = DISTANT_DEFINITION_BAND, cut::Real = 0.95,
        min_defs::Integer = MIN_DISTANT_DEFINITION_DEFS
    )
    byid = Dict{Tuple{String, NodeId}, Int}((d.file, d.id) => i for (i, d) in enumerate(table.defs))
    scored = Tuple{ParsedFile, Int, Vector{Location}}[]
    for f in files
        scopes_query_for(f) === nothing && continue
        gaps, users = nearest_uses(f, byid)
        for di in sort!(collect(keys(gaps)))
            d = table.defs[di]
            use = f.index.units[users[di]]
            locations = Location[
                Location(f.file, d.line, d.name),
                Location(
                    f.file, use.firstline, unit_name(use, f.index),
                    string("nearest use of ", d.name)
                ),
            ]
            push!(scored, (f, gaps[di], locations))
        end
    end
    return scored_findings(RELATIONAL.distant_definition, scored, band, cut, min_defs)
end
