# Dependencies running against the grain the code itself established. Contract the file
# graph by directory and read the traffic between two directories in each direction. When
# one direction carries almost all of it, the code has settled on a layering, and each
# reference going the other way runs against it: an import to drop and a definition to
# move. The grain comes from the corpus, so no declared layer order and no configuration is
# involved, which is the reason to prefer this over a layer-violation check nobody keeps up
# to date.
#
# Higher dominance is worse, which is the direction the band model expects. A pair at 60/40
# is a genuinely mutual dependency, a cycle rather than a violated grain; a pair at 98/2 is
# an established direction with a handful of references running backwards.
#
# Name-based and lexical like the rest of placement: an edge is a reference the linkage
# admits, never a type or a dispatch.

# Absolute band on the dominance percent, the share of the traffic between two directories
# running the majority way. Measured over 69 qualifying pairs from nine corpora in five
# languages: Documenter.jl, Pkg.jl, Pluto.jl, DataFrames.jl and Julia's Base, Flask,
# ripgrep, Laravel, and the julia-vscode extension.
#
# What the measurement fixes is where a settled direction begins. The distribution runs
# continuously from 51 to 99 with no gap to sit in. Pairs at 83 and below couple both ways
# in earnest, and mutual dependency is a cycle rather than a violated grain, which is
# `:dependency_cycle`'s question and not this one; the warn threshold sits above that
# cluster. The high threshold sits where the majority direction is one-way enough that
# going against it reads as an anomaly rather than as a design.
#
# What the measurement does not fix is the size of the resulting edit, and the band must
# not be read as bounding it. Dominance is a ratio, so a pair with a large majority side
# clears 95 while carrying a large minority side: CommonMark.jl's root against `writers`
# scores 95, exactly at the high threshold, on 15 references spread over 14 file edges. A
# high score says the direction is one-way. It never says one import removal restores it.
# `BACK_EDGE_EDGE_CAP` is what keeps that difference out of the gate.
const BACK_EDGE_BAND = (85, 95)

# The majority direction needs at least this much traffic before the pair has a grain to
# violate. Two directories exchanging a handful of references each way have settled on no
# direction, and reading one as dominant would be reading noise.
const BACK_EDGE_MIN_MAJOR = 10

# The widest minority side that still names a bounded edit. A pair spreading its minority
# direction over more file edges than this reports below `:high` whatever its dominance, so
# one architectural observation cannot become a burst of gate errors when there is no single
# edit to propose. The same reasoning as a cycle component too tangled to cut: report it,
# stop pretending it names an edit.
#
# Measured over the twelve calibration corpora. Of the seventeen pairs reaching the high
# threshold, sixteen spread their minority side over one to four file edges and the
# seventeenth over fourteen, CommonMark.jl's root against `writers`. Nothing lands between
# five and thirteen, so the cap sits in a real gap rather than on a judgement call. The
# pairs it excludes are the wide ones in the warn band, at 7, 8, 18, 56 and 135 edges,
# which are tangles by any reading.
const BACK_EDGE_EDGE_CAP = 5

# The corpus needs this many bidirectional directory pairs before the dominance percentile
# means anything; under it only the absolute band fires, as cohesion does on a thin corpus.
# `cluster_low_cohesion`, `cluster_misplaced` and `cluster_scattered` each expose the
# equivalent floor as a keyword. This one is fixed because `cluster_back_edge` already takes
# seven parameters and an eighth would trip `parameter_count` at its `:high` band, putting
# the rule into Dendro's own error floor. Retune it here rather than per call.
const MIN_BACK_EDGE_PAIRS = 5

"""
    cluster_back_edge(files, fg, table; band=$BACK_EDGE_BAND, cut=0.95, min_major=$BACK_EDGE_MIN_MAJOR, visible=corpus_visibility(files, table)) -> Vector{Finding}

References running against a directory pair's established direction, reported as
`:back_edge`. The file graph contracted by directory gives the reference weight between
each pair of directories in both directions; a pair coupled both ways, whose majority
direction clears `min_major`, scores the dominance percent, `100 * major / (major + minor)`.
Each finding carries the absolute `band` on that percent and the corpus percentile over
the bidirectional pairs, fired when either trips. One finding is emitted per file edge in
the minority direction, since the edit is to an edge rather than to a pair.

A pair whose minority direction spans more than `BACK_EDGE_EDGE_CAP` file edges reports
below `:high` whatever its dominance. Dominance fixes where a settled direction begins and
says nothing about how far back the way home is, so a pair with a large majority side
clears the high threshold while spreading its minority side over a dozen files. Emitting
those at `:high` turns one architectural observation into a dozen gate errors and offers
no bounded edit for any of them. The findings still name every minority edge, so nothing
is hidden; they stop claiming an edit the pair cannot deliver. This follows the same
reasoning as a cycle component too tangled to cut, which is reported as a tangle rather
than as a feedback set.

The locations are the minority edge's import statement first, where the language declares
one, then every reference site across the edge. That is wider than the per-file metrics
report and it is deliberate: a diff that adds a use of an already-imported name introduces
a back edge without touching the import's line, and locating the finding at the import
alone would drop it under [`analyze`](@ref)'s `base` scoping, which is the mode review runs
in.

The consequence lands in the gate. `errors(; since)` keys a finding by its location set, so
an edge's key grows as references accumulate across it, and adding one to an established
back edge re-reports a violation the base already carried. That is the intended reading
rather than a defect: the ratchet exists to catch worsening, and one more reference across
a back edge is worsening.

Known failure modes. Deliberate callbacks and plugin registration point backwards by
design; the answer is `dendro-ignore: back_edge`, not a smarter model. A corpus whose
files all sit in one directory contracts to one group and is scored not at all, since
file-to-file bidirectionality is ordinary and reading it would be noise. Test directories
referencing source, and source referencing test fixtures, are usually answered by
`analyze`'s `ignore` patterns.
"""
function cluster_back_edge(
        files::Vector{ParsedFile}, fg::FileGraph, table::SymbolTable;
        band::Tuple{Int, Int} = BACK_EDGE_BAND, cut::Real = 0.95,
        min_major::Integer = BACK_EDGE_MIN_MAJOR,
        visible::Dict{String, Dict{String, Vector{Int}}} = corpus_visibility(files, table)
    )
    findings = Finding[]
    mg = module_graph(fg)
    scored = dominated_pairs(mg, min_major)
    isempty(scored) && return findings

    dominances = sort([p[3] for p in scored])
    enough = length(scored) >= MIN_BACK_EDGE_PAIRS
    flagged = Tuple{Tuple{Int, Int}, Int, Symbol, Union{Float64, Nothing}}[]
    for (minority, majority, dominance) in scored
        absolute, pct = two_scores(dominance, dominances, band, enough)
        fires(absolute, pct, cut) || continue
        edges = minority_edges(fg, mg, minority, majority)
        # A minority side spread this wide proposes no single edit, so it is reported and
        # not gated. Demoted rather than dropped: the observation stands, the claim does not.
        reported = length(edges) > BACK_EDGE_EDGE_CAP && absolute === :high ? :warn : absolute
        for edge in edges
            push!(flagged, (edge, dominance, reported, pct))
        end
    end
    isempty(flagged) && return findings

    sites = edge_reference_sites(files, table, fg, Set{Tuple{Int, Int}}(e[1] for e in flagged), visible)
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    for (edge, dominance, absolute, pct) in flagged
        locations = [fg.edges[edge].declared; get(() -> Location[], sites, edge)]
        file = fg.files[edge[1]]
        sup = is_suppressed(get(() -> Directive[], directives, file), locations[1].line, RELATIONAL.back_edge)
        push!(findings, Finding(RELATIONAL.back_edge, locations, dominance, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end

# Every directory pair coupled in both directions, as `(minority group, majority group,
# dominance percent)`, keeping only pairs whose majority direction carries `min_major`
# references. Each unordered pair is visited once, from its lower-numbered group, and an
# even split takes the lower group as the minority so the result never depends on which
# direction a `Dict` yielded first.
function dominated_pairs(mg::ModuleGraph, min_major::Integer)
    out = Tuple{Int, Int, Int}[]
    for (a, b) in sort!(collect(keys(mg.edges)))
        a < b || continue
        back = get(mg.edges, (b, a), 0)
        back == 0 && continue
        forward = mg.edges[(a, b)]
        major, minor = max(forward, back), min(forward, back)
        major >= min_major || continue
        minority, majority = forward <= back ? (a, b) : (b, a)
        push!(out, (minority, majority, round(Int, 100 * major / (major + minor))))
    end
    return out
end

# The file edges running from one group into another, sorted. A pair's finding is emitted
# per file edge rather than per pair: the agent edits an edge.
function minority_edges(fg::FileGraph, mg::ModuleGraph, minority::Int, majority::Int)
    sources = Set{Int}(mg.members[minority])
    targets = Set{Int}(mg.members[majority])
    return sort!([e for e in keys(fg.edges) if e[1] in sources && e[2] in targets])
end

# Every reference site behind each of the `wanted` file edges. The file graph records an
# edge's weight and the names on it, not where each reference sits, and a finding that
# has to survive diff scoping needs the sites themselves. Resolved from the same
# `visible` map the graph was built from, so the sites are the references that built it.
# A reference matching several definitions in one target file names that edge once.
function edge_reference_sites(
        files::Vector{ParsedFile}, table::SymbolTable, fg::FileGraph,
        wanted::Set{Tuple{Int, Int}}, visible::Dict{String, Dict{String, Vector{Int}}}
    )
    out = Dict{Tuple{Int, Int}, Vector{Location}}()
    sources = Set{String}(fg.files[e[1]] for e in wanted)
    lines = Dict{String, Dict{NodeId, Int}}()
    unit_labels = Dict{String, Vector{String}}()
    for (f, ref, candidates) in corpus_references(files, visible)
        f.file in sources || continue
        src = fg.index[f.file]
        for di in candidates
            edge = (src, get(fg.index, table.defs[di].file, 0))
            edge in wanted || continue
            byid = get!(() -> reference_lines(f), lines, f.file)
            labels = get!(() -> String[unit_name(u, f.index) for u in f.index.functions], unit_labels, f.file)
            unit = ref.unit == 0 ? "" : labels[ref.unit]
            push!(get!(() -> Location[], out, edge), Location(f.file, byid[ref.id], unit))
        end
    end
    for sites in values(out)
        unique!(sort!(sites; by = loc -> (loc.line, loc.unit)))
    end
    return out
end

# The 1-based line of every reference node in one file, keyed the way an `UnboundRef`
# carries its identity.
reference_lines(f::ParsedFile) =
    Dict{NodeId, Int}(nodeid(n) => line_of(n) for n in f.index.scope_captures.refnodes)
