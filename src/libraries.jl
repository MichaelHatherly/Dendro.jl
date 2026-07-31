# Duplication against code the project does not own. Every other reading Dendro makes is
# one corpus judged against itself; this one asks whether the author wrote something a
# library they already ship with does for them. Corpus A is the project, corpora B, C, ...
# are libraries, and the pass is directional: it reports A, never B.
#
# A library is read and never judged. It never enters the baseline, the symbol resolution
# of A, either graph, the per-file rules, the existing clone passes, or the corpus a
# `Scope` is built over, so a dependency ten times the project's size neither moves the
# percentile nor fills the report with code nobody can edit.
#
# That separation decides the shape of the finding. `Scope.rels` is built from corpus files
# alone, so a `Location` pointing into a library throws under `analyze(; base)`. Every
# library fact therefore goes in the label, which `fkey` ignores by construction, so
# upgrading a dependency never re-reports an unchanged finding.
#
# Still inside the syntactic bargain: subtree hashes and tree shape, no symbol resolution
# across the corpus boundary, always within one language.

# Directory names that name a package's sources rather than the package, so a library
# pointed at `dep/src` reads as `dep`. The fallback stops at one level: a depot path like
# `~/.julia/packages/IterTools/A1b2C/src` yields `A1b2C`, and no rule that strips version
# slugs is going to be right across ecosystems. Name a library in the config instead.
const SOURCE_DIR_NAMES = ("src", "lib", "source", "sources")

# The display name a root implies: its own basename, or the parent's when the basename
# only says "sources live here".
function derived_name(root::String)
    base = basename(root)
    lowercase(base) in SOURCE_DIR_NAMES || return base
    parent = basename(dirname(root))
    return isempty(parent) ? base : parent
end

# Resolve a root or list of roots to absolute directories. `expanduser` and `abspath` run
# here rather than at each call site, so the API and the config agree on what a path means
# and a relative root resolves against the process directory instead of being carried
# around unresolved. A root that is not a directory throws, as `collect_corpus` does for a
# scanned path: a library that quietly resolves to nothing turns the gate off.
function library_roots(roots)::Vector{String}
    paths = roots isa AbstractString ? [String(roots)] : collect(String, roots)
    isempty(paths) && error("Dendro: a library needs at least one root")
    out = String[]
    for p in paths
        resolved = normpath(abspath(expanduser(p)))
        isdir(resolved) || error("Dendro: library root is not a directory: $p")
        push!(out, resolved)
    end
    return out
end

"""
    Library(roots; ignore = String[])
    Library(name, roots; ignore = String[])

A reference corpus: source Dendro reads to compare the project against, and never scores.
`roots` is one directory or a list of them, `ignore` a list of gitignore-style patterns as
[`analyze`](@ref)'s own `ignore`. Pass a `Vector{Library}` as `analyze`'s `libraries` to
report `:library_duplicate` and `:library_near_duplicate` findings at the sites in the
project that a library already implements.

```julia
Library("Base", "/usr/local/julia/base"; ignore = ["precompile.jl"])
Library("MyDep", ["dep/src", "dep/ext"])
Library("~/.julia/packages/IterTools/A1b2C/src")     # name derived
```

Absent a `name`, the first root's basename is used, falling back to the parent's when that
basename is a conventional source directory, so `dep/src` reads as `dep`. The name is
display only: nothing keys on it, and a version slug in a depot path is not worth guessing
at, so name a library in the config when the path does not say it.

Roots are expanded and made absolute on construction, and a root that is not a directory
throws.
"""
struct Library
    name::String
    roots::Vector{String}
    ignore::Vector{String}

    Library(name::AbstractString, roots, ignore) =
        new(String(name), library_roots(roots), collect(String, ignore))
end

Library(name::AbstractString, roots::Union{AbstractString, AbstractVector}; ignore = String[]) =
    Library(name, roots, ignore)

function Library(roots::Union{AbstractString, AbstractVector}; ignore = String[])
    resolved = library_roots(roots)
    return Library(derived_name(first(resolved)), resolved, ignore)
end

# A caller's `libraries` keyword read as reference corpora: `Library` values pass through,
# a bare path becomes a library named after its root. A string is one root rather than a list
# of roots, and a bare `Library` is one library rather than something to iterate, both being
# the reading a caller naming a single thing means.
as_libraries(library::Library)::Vector{Library} = Library[library]

as_libraries(libraries)::Vector{Library} =
    Library[l isa Library ? l : Library(l) for l in (libraries isa AbstractString ? [libraries] : libraries)]

# Default near-miss cutoff for a cross-corpus match, `max(|LCS|/|a|, |LCS|/|r|)`. Either
# side being substantially covered is a match; the coverage score then says what it costs
# the project.
#
# Higher than the within-corpus `DEFAULT_THRESHOLD`, and measured rather than inherited.
# Across ten Julia projects against their declared dependencies the population decays
# smoothly, 618 findings at 0.85, 207 at 0.90, 51 at 0.95, none at 0.98, so there is no gap
# to sit in and this is a stated noise-against-recall trade instead. 0.85 reports some sixty
# findings per project, too many to read; 0.95 reports five and loses both of the true
# positives the sample turned up, whose similarity sits between the two. 0.90 is the last
# cutoff that keeps the signal.
const DEFAULT_LIBRARY_THRESHOLD = 0.9

# The coverage percent a match against a public whole library function needs before it
# reports at `:high` and reaches the gate. Below half, "import this instead" is an edit
# inside a function you keep rather than a deletion, which is a suggestion and not a
# violation.
const DEFAULT_LIBRARY_GATE_COVERAGE = 50

# References a finding's label names before it falls back to a count, the shape a
# `FileEdge`'s `top_names` and `:split_audience`'s consumer list already use.
const LIBRARY_EVIDENCE_MAX = 3

# One indexed subtree of a library: what the join needs, what a label names, and nothing
# that could turn a library site into a `Location`. `sequence` and `histogram` carry the
# near-miss features, filled for whole units at `:unit` grain and for every anchor at
# `:anchor`: a block always takes part in the exact join, where the hash is the whole
# verdict, and only the wider grain compares one approximately.
struct RefAnchor
    language::Symbol
    hash::UInt64
    size::Int
    sequence::Vector{UInt64}
    histogram::Dict{String, Int}
    whole_unit::Bool
    symbol::String
    public::Bool
    file::String
    line::Int
end

"""
    ReferenceIndex

One [`Library`](@ref) parsed and indexed: its display `library` name, every anchor it
holds, `by_hash` for the exact join, `units`, the indices of the whole-unit anchors, and
the `grain` it was built at, which decides how many of those anchors carry near-miss
features. Built by [`reference_index`](@ref), read and never scored.

The grain is a field so a cached index describes itself: serving a `:unit` index to the
`:anchor` pass would leave every block without features and silently under-report.
"""
struct ReferenceIndex
    library::String
    by_hash::Dict{Tuple{Symbol, UInt64}, Vector{Int}}
    anchors::Vector{RefAnchor}
    units::Vector{Int}
    grain::Symbol
end

# The anchors the near pass compares: whole units, or every anchor at the wider grain.
near_candidates(ref::ReferenceIndex) = ref.grain === :anchor ? eachindex(ref.anchors) : ref.units

# The lookup miss, shared so an absent `(language, hash)` returns this rather than building
# an empty vector per lookup. The exact join asks once per project anchor and most anchors
# match nothing, so the fallback is on the hot path.
const NO_ANCHORS = Int[]

# The granularities the near pass runs at. `:unit` compares whole functions on both sides;
# `:anchor` compares every anchor, which is what finds a library function's shape appearing,
# edited, inside a larger function of the project's. Measured over five projects, the wider
# grain proposes three to four times as many candidate pairs and costs three and a half to
# five times the LCS work, for four to twenty percent more findings in a population that
# never gates, so it is off by default and a project opts in.
const LIBRARY_GRAINS = (:unit, :anchor)

# Whether each library definition is part of that library's public API, and the top-level
# function ranges an anchor attributes through. Only as much of the corpus resolution as
# publicness needs: `visible_defs` and `corpus_references`, the two expensive halves of
# `resolve_linkage`, are skipped, since nothing here asks what the library references.
#
# The unknown-language default is inverted here, deliberately. `:unreferenced` reads a
# definition in a language with no `LINKAGES` entry as public, the safe direction where an
# unverifiable definition must not be called dead. Here public is what promotes a finding
# to `:high` and puts it in the gate, so the safe direction is the other one: a library
# whose linkage Dendro cannot resolve reads as private, and nothing gates on a guess.
# Written out here rather than routed through the reachability path, so the two defaults
# cannot later be "fixed" into agreement.
function reference_publicness(files::Vector{ParsedFile})
    table = corpus_symbols(files)
    surface = public_surface(files, DeclaredLinkage(files, Corpus(files)))
    languages = Dict{String, Symbol}(f.file => f.language for f in files)
    units = Dict{String, Vector{FunctionUnit}}(f.file => f.index.functions for f in files)
    public = falses(length(table.defs))
    ranges = Dict{String, Vector{Tuple{Int, Int, Int}}}()
    for (di, d) in enumerate(table.defs)
        link = get(LINKAGES, languages[d.file], nothing)
        public[di] = link !== nothing && link.is_public(d, get(() -> Set{String}(), surface, d.file))::Bool
        d.unit == 0 && continue
        from, to = TreeSitter.byte_range(units[d.file][d.unit].node)
        push!(get!(() -> Tuple{Int, Int, Int}[], ranges, d.file), (from, to, di))
    end
    return table, public, ranges
end

# One library file's path as a label shows it: relative to the root it was found under, so
# a depot's version slug never reaches a finding and a dependency upgrade never rewrites
# one.
function root_relative(file::String, roots::Vector{String})
    for r in roots
        startswith(file, r) && return relpath(file, r)
    end
    return file
end

"""
    reference_index(library; min_size, grain, profiles, exclude, cache) -> ReferenceIndex

Parse `library`'s roots and index every anchor in them: whole function units and the
blocks inside them, at the floors [`anchor_floor`](@ref) already sets, each attributed to
the top-level definition enclosing it and to that definition's publicness in this library.

Indexing blocks as well as whole units is what makes partial duplication fall out of the
exact join with no further mechanism, and what makes the project side's maximality filter
sound.

Parsing takes a lighter path than a scan: a file that is never scored needs no binding
resolution, no pattern queries, and no suppression directives. A file whose `realpath` is
in `exclude`, the corpus being scanned, is dropped before indexing, since pointing a
library at the project's own source would report every function as a duplicate of itself.

`grain` decides which anchors carry the near pass's features: `:unit` stores them for whole
functions only, `:anchor` for every anchor, which roughly doubles the index and is what the
opt-in wider near pass reads.

The result memoizes to disk in a Dendro scratch space, `\$DENDRO_CACHE_DIR` when that names
one, keyed by the format and version of the index, `min_size`, the grain, and the size and
mtime of every file it indexed. Indexing is the dominant cost of a cross-corpus scan and a
dependency set changes rarely, so this is what keeps the pass usable on every CI run.
`cache = false` skips it.

An entry untouched by any scan for a week is collected, swept on write at most once a day.
A dependency bump moves the key rather than replacing the entry under it, so without that
the space grows for as long as the dependencies move.
"""
function reference_index(
        library::Library; min_size::Integer, grain::Symbol = :unit,
        profiles::Dict{Symbol, LanguageProfile} = PROFILES, exclude::Set{String} = Set{String}(),
        cache::Bool = true
    )
    grain in LIBRARY_GRAINS || error("Dendro: unknown library grain $grain")
    paths = collect_corpus(library.roots, library.ignore, nothing; profiles)
    filter!(p -> !(realpath(p) in exclude), paths)
    key = cache ? reference_key(library, paths, min_size, grain, profiles) : ""
    if cache
        hit = load_reference(key)
        # The key already covers the grain; the field is checked too, since a wrong index
        # here reports nothing rather than failing, which is the failure mode to refuse.
        hit === nothing || hit.grain === grain && return hit
    end
    index = build_reference_index(library, paths, min_size, grain, profiles)
    cache && store_reference(key, index)
    return index
end

function build_reference_index(
        library::Library, paths::Vector{String}, min_size::Integer, grain::Symbol,
        profiles::Dict{Symbol, LanguageProfile}
    )
    files = parse_corpus(paths; profiles, bindings = false, directives = false)
    table, public, ranges = reference_publicness(files)

    anchors = RefAnchor[]
    by_hash = Dict{Tuple{Symbol, UInt64}, Vector{Int}}()
    units = Int[]
    empty_ranges = Tuple{Int, Int, Int}[]
    for f in files
        shown = root_relative(f.file, library.roots)
        topfns = get(ranges, f.file, empty_ranges)
        for unit in functions(f.index)
            st = subtrees(unit, f.index)
            for s in st
                floor = anchor_floor(s.node, f.index, min_size)
                (floor === nothing || s.size < floor) && continue
                whole = is_function(s.node, f.index)
                sequence, histogram = near_features(s, st, f, grain)
                from, to = TreeSitter.byte_range(s.node)
                di = enclosing_def(topfns, from, to)
                push!(
                    anchors, RefAnchor(
                        f.language, s.hash, s.size, sequence, histogram,
                        whole, di == 0 ? "" : table.defs[di].name, di != 0 && public[di],
                        shown, Int(TreeSitter.start_point(s.node).row) + 1,
                    )
                )
                push!(get!(() -> Int[], by_hash, (f.language, s.hash)), length(anchors))
                whole && push!(units, length(anchors))
            end
        end
    end
    return ReferenceIndex(library.name, by_hash, anchors, units, grain)
end

# The near-miss features one anchor carries: the pre-order hash sequence the LCS compares
# and the histogram the radius query reads. A whole unit reuses the walk `st` already holds;
# a block below one needs the same walk from its own node, cheap beside the parse and only
# paid at the wider grain. At `:unit` grain a block carries neither, since the exact hash is
# the whole verdict there.
function near_features(s::Subtree, st::Vector{Subtree}, f::ParsedFile, grain::Symbol)
    if is_function(s.node, f.index)
        return preorder_hashes(st), histogram_of(st)
    elseif grain === :anchor
        sub = anchor_subtrees(s.node, f.index)
        return preorder_hashes(sub), histogram_of(sub)
    end
    return UInt64[], Dict{String, Int}()
end

# The subtrees of one anchor below a whole unit, the same bottom-up walk `subtrees` runs
# from a unit's node.
anchor_subtrees(node::TreeSitter.Node, index::QueryIndex) =
    (acc = Subtree[]; collect_subtrees!(acc, node, index); acc)

"""
    reference_indices(libraries, corpus; min_size, profiles) -> Vector{ReferenceIndex}

One [`ReferenceIndex`](@ref) per library, with `corpus`, the paths being scanned, excluded
from every one of them. Empty and free when no library is configured: absent `libraries`
there is nothing to switch on, only something to point at, so the feature is self-disabling
and an unconfigured scan pays nothing.
"""
function reference_indices(
        libraries::Vector{Library}, corpus::Vector{String};
        min_size::Integer, grain::Symbol = :unit,
        profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    isempty(libraries) && return ReferenceIndex[]
    exclude = Set{String}(realpath(p) for p in corpus)
    return ReferenceIndex[reference_index(l; min_size, grain, profiles, exclude) for l in libraries]
end

# One library anchor a project anchor matched, and what that match costs the project. The
# evidence a label is built from, and the reason a finding needs no second `Location`.
struct RefMatch
    library::String
    symbol::String
    public::Bool
    whole_unit::Bool
    file::String
    line::Int
    coverage::Int
end

# How much of the project's enclosing unit the matched region is, as a percent. The
# denominator is always the project side, because the question is: how much of this
# function of mine is already in a library. One number, monotone in how much code the edit
# deletes, and sortable against itself.
coverage_percent(matched::Integer, unit::Integer) =
    unit == 0 ? 0 : round(Int, 100 * matched / unit)

# Every library anchor whose shape equals `hash` in `language`, as evidence.
function reference_matches(
        references::Vector{ReferenceIndex}, language::Symbol, hash::UInt64, coverage::Int
    )
    out = RefMatch[]
    for ref in references
        for i in get(ref.by_hash, (language, hash), NO_ANCHORS)
            a = ref.anchors[i]
            push!(out, RefMatch(ref.library, a.symbol, a.public, a.whole_unit, a.file, a.line, coverage))
        end
    end
    return out
end

# One reference as a label names it: the library-qualified symbol, whether it is
# importable, and where it sits relative to the library's root.
reference_note(m::RefMatch) = string(
    m.library, isempty(m.symbol) ? "" : ".", m.symbol,
    m.public ? " public" : " internal", ", ", m.file, ":", m.line,
)

# A finding's evidence as a label: the best references named, the rest counted. Every
# library fact lives here rather than in a second `Location`, since a location outside the
# corpus would throw under diff scoping and would put the library's path, version slug and
# all, into the ratchet key.
function evidence_label(matches::Vector{RefMatch})
    shown = min(length(matches), LIBRARY_EVIDENCE_MAX)
    parts = String[reference_note(matches[i]) for i in 1:shown]
    length(matches) > shown && push!(parts, string("+", length(matches) - shown, " more"))
    return join(parts, "; ")
end

# One finding per project site a library covers, the emission both cross-corpus passes
# share. Evidence is ordered best first, public before internal, then importable before
# not, then by coverage, then lexicographically so the order is deterministic.
#
# The band is the only place publicness and granularity combine. A match against a public
# whole library function at or above `gate_coverage` is importable: there is a name to call
# instead, so it reports `:high` and reaches the gate. Everything else warns. Half a
# function cannot be imported however public the function holding it, and a private one has
# no name to call, though it still says the library solved this and you solved it again.
#
# `gate_coverage` is `nothing` for a pass that never gates, which is how the near pass says
# so: measured precision on its `:high` findings was 11% against the exact pass's 33%, and
# at the band it would have shipped with it put some eight gate errors into a healthy
# project, which is an unsatisfiable gate rather than a signal.
#
# The value is the best-ranked match's coverage, not the site's highest. Where a public match
# and a private one both cover a site, the ranking puts the public one first and the value
# follows it, so the number and the band always describe the same match, the one naming an
# edit. Reading the highest instead would rank a site by how redundant it is while banding it
# by something else.
function library_finding(
        metric::Symbol, site::Location, matches::Vector{RefMatch},
        suppressed::Bool, gate_coverage::Union{Integer, Nothing}
    )
    sort!(matches; by = m -> (!m.public, !m.whole_unit, -m.coverage, m.library, m.file, m.line))
    best = first(matches)
    band = gate_coverage !== nothing && best.public && best.whole_unit &&
        best.coverage >= gate_coverage ? :high : :warn
    labelled = Location(site.file, site.line, site.unit, evidence_label(matches))
    return Finding(metric, [labelled], best.coverage, band, nothing, :flag, suppressed)
end

# Findings sorted the way both cross-corpus passes report: the costliest redundancy first,
# then by site so the order is fixed whatever the corpus traversal produced.
sort_library_findings!(findings::Vector{Finding}) =
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))

# Whether a matched anchor's nearest enclosing anchor also matched, in which case the
# larger redundant region is the finding and this one sits inside it.
#
# Checking the nearest enclosing anchor alone is sound because exact matching is monotone
# downward: equal hashes mean every subtree of the project's anchor has an equal-hash
# counterpart in the reference anchor, at the same size and so over the same floor and in
# the reference index. Every anchor descendant of a matched anchor therefore matches too,
# and "the nearest enclosing anchor matched" and "some enclosing anchor matched" say the
# same thing. That holds only because the reference side indexes blocks as well as whole
# units; index only whole units there and this shortcut becomes wrong, silently.
subsumed_match(node::TreeSitter.Node, indexed::Set{NodeId}, matched::Set{NodeId}) =
    something(nearest_anchor(p -> (id = nodeid(p); id in indexed ? id in matched : nothing), node), false)

"""
    cluster_library_duplicates(files, references; min_size, gate_coverage) -> Vector{Finding}

Project code whose shape a library already holds exactly, reported as
`:library_duplicate`, one finding per surviving project anchor. Every anchor in `files` is
looked up by `(language, hash)` in each [`ReferenceIndex`](@ref), so shapes never cross
grammars, and a maximality filter keeps the largest redundant region rather than reporting
each block inside it again.

The value is coverage: how much of the project's enclosing unit the matched region is, as
a percent. A hash lookup per anchor, so the cost is independent of how large the libraries
are, which is what lets this pass gate. Suppressed when the site carries a
`dendro-ignore: library_duplicate` directive.
"""
function cluster_library_duplicates(
        files::Vector{ParsedFile}, references::Vector{ReferenceIndex};
        min_size::Integer = DEFAULT_MIN_SIZE,
        gate_coverage::Integer = DEFAULT_LIBRARY_GATE_COVERAGE
    )
    findings = Finding[]
    for f in files
        for unit in functions(f.index)
            name = unit_name(unit, f.index)
            st = subtrees(unit, f.index)
            total = st[end].size
            indexed = Set{NodeId}()
            matched = Set{NodeId}()
            hits = Dict{NodeId, Vector{RefMatch}}()
            for s in st
                floor = anchor_floor(s.node, f.index, min_size)
                (floor === nothing || s.size < floor) && continue
                id = nodeid(s.node)
                push!(indexed, id)
                found = reference_matches(references, f.language, s.hash, coverage_percent(s.size, total))
                isempty(found) && continue
                push!(matched, id)
                hits[id] = found
            end
            for s in st
                id = nodeid(s.node)
                id in matched || continue
                subsumed_match(s.node, indexed, matched) && continue
                line = Int(TreeSitter.start_point(s.node).row) + 1
                sup = is_suppressed(f.directives, line, RELATIONAL.library_duplicate)
                push!(
                    findings, library_finding(
                        RELATIONAL.library_duplicate, Location(f.file, line, name),
                        hits[id], sup, gate_coverage
                    )
                )
            end
        end
    end
    return sort_library_findings!(findings)
end

# The anchors the near pass compares, grouped by language and paired with the library each
# came from. At `:unit` grain that is the whole functions and the blocks stay in the exact
# join, where the hash is the whole verdict; at `:anchor` it is everything the index holds
# features for.
function reference_units(references::Vector{ReferenceIndex})
    out = Dict{Symbol, Vector{Tuple{String, RefAnchor}}}()
    for ref in references
        for i in near_candidates(ref)
            a = ref.anchors[i]
            push!(get!(() -> Tuple{String, RefAnchor}[], out, a.language), (ref.library, a))
        end
    end
    return out
end

"""
    ProjectRegion

One region of the project the near pass compares: the `location` to report it at, the
near-miss features, the `digest` that tells an exact match apart, whether it is a `whole`
function unit, and `unit_size` and `unit_line`, the size and first line of the unit
enclosing it.

`unit_size` is the coverage denominator and stays the whole unit even when the region is a
block inside one, because the question the score answers is how much of *this function of
mine* is already in a library. The match test reads the region's own sequence instead, so
whether there is a finding and what it costs stay separate readings.

`unit_line` is what identifies that enclosing unit. A name does not: Julia puts several
methods of one name in one file, so keying on the name reads a block inside one method as
already covered by a match against another.
"""
struct ProjectRegion
    language::Symbol
    location::Location
    suppressed::Bool
    sequence::Vector{UInt64}
    histogram::Dict{String, Int}
    digest::UInt64
    whole::Bool
    unit_size::Int
    unit_line::Int
end

# A whole function is its own enclosing unit, so its location's line is that unit's line.
ProjectRegion(u::CloneUnit) = ProjectRegion(
    u.language, u.location, u.suppressed, u.sequence, u.histogram, u.digest,
    true, u.size, u.location.line,
)

"""
    project_regions(files, min_size, grain) -> Vector{ProjectRegion}

The regions of `files` the near pass compares. At `:unit` grain that is
[`clone_units`](@ref), the whole functions the within-corpus pass reads. At `:anchor` it is
every anchor, so a library function's shape appearing edited inside a larger function of the
project's is proposed, which the unit grain cannot see: a block and the function containing
it land in different size bands, and the banding is what keeps the query off a full pairwise
comparison.
"""
function project_regions(files::Vector{ParsedFile}, min_size::Integer, grain::Symbol)
    metric = RELATIONAL.library_near_duplicate
    grain === :anchor ||
        return ProjectRegion[ProjectRegion(u) for u in clone_units(files, min_size, metric)]

    regions = ProjectRegion[]
    for f in files
        for unit in functions(f.index)
            st = subtrees(unit, f.index)
            name = unit_name(unit, f.index)
            total = st[end].size
            for s in st
                floor = anchor_floor(s.node, f.index, min_size)
                (floor === nothing || s.size < floor) && continue
                whole = is_function(s.node, f.index)
                sub = whole ? st : anchor_subtrees(s.node, f.index)
                line = Int(TreeSitter.start_point(s.node).row) + 1
                push!(
                    regions, ProjectRegion(
                        f.language, Location(f.file, line, name),
                        is_suppressed(f.directives, line, metric),
                        preorder_hashes(sub), histogram_of(sub), s.hash, whole, total,
                        unit.firstline,
                    )
                )
            end
        end
    end
    return regions
end

"""
    cluster_library_near_duplicates(files, references; min_size, threshold, radius_factor, grain) -> Vector{Finding}

Project code a library implements approximately, reported as `:library_near_duplicate`, one
finding per project region. Within one language, the copy-paste-then-edit the exact join
cannot see: adding one guard clause changes the shape and the hash with it.

The reference side is indexed and the project's queried against it, size-banded as
[`banded_candidates`](@ref) proposes and confirmed by an LCS. A pair matches when either
side is substantially covered, `max(|LCS|/|a|, |LCS|/|r|)` at or above `threshold`, since a
library function almost wholly contained in a project function is the finding as much as
the other way round. The value is coverage against the project's enclosing unit, so the
match test says whether there is a finding and the score says what it costs. Pairs with
equal digests are dropped: the exact pass already has them.

`grain` decides what is compared. `:unit` reads whole functions on both sides. `:anchor`
reads every anchor, which is what proposes approximate partial containment, a library
function's shape appearing edited inside a much larger function of the project's; a region
whose enclosing unit matched is dropped, so the larger redundant region is the finding. It
needs a reference index built at the same grain, costs three to four times the candidate
pairs, and is off by default.

Every finding reports at `:warn`, so this pass never reaches [`errors`](@ref). That is
measured, not cautious: over ten Julia projects against their declared dependencies, hand
classification put precision on its would-be `:high` findings at 11% against the exact
pass's 33%, and it does not improve with a higher cutoff, which discards the true positives
before the coincidences. A weaker match test (`|LCS|` against the *shorter* side, where the
within-corpus pass reads the longer) against a pool of thousands of library units is what
separates the two. Vocabulary this pass reads as similar shape is a proposal to check, not
a violation to gate on.
"""
function cluster_library_near_duplicates(
        files::Vector{ParsedFile}, references::Vector{ReferenceIndex};
        min_size::Integer = DEFAULT_MIN_SIZE, threshold::Real = DEFAULT_LIBRARY_THRESHOLD,
        radius_factor::Real = DEFAULT_RADIUS_FACTOR, grain::Symbol = :unit
    )
    regions = project_regions(files, min_size, grain)
    pools = reference_units(references)
    bylang = by_language(regions)

    matches = Dict{Int, Vector{RefMatch}}()
    thr = Float64(threshold)
    for language in sort!(collect(keys(bylang)))
        idxs = bylang[language]
        pool = get(pools, language, NO_REF_UNITS)
        isempty(pool) && continue
        library_pairs!(matches, regions, idxs, pool, thr, Float64(radius_factor))
    end

    findings = Finding[]
    covered = matched_units(regions, matches)
    for i in sort!(collect(keys(matches)))
        r = regions[i]
        (!r.whole && (r.location.file, r.unit_line) in covered) && continue
        push!(
            findings, library_finding(
                RELATIONAL.library_near_duplicate, r.location, matches[i], r.suppressed, nothing
            )
        )
    end
    return sort_library_findings!(findings)
end

# The units that matched, keyed by file and first line. A region below one of them is inside
# a redundancy already reported whole, and the larger region is the finding. Only the wider
# grain produces regions below a unit at all. Approximate matching is not monotone the way
# exact matching is, so this is a reporting choice rather than a soundness one: a block whose
# enclosing function already matched names no separate edit.
#
# By line and not by name, since Julia puts several methods of one name in one file and a
# name would read a block inside one method as covered by a match against another.
function matched_units(regions::Vector{ProjectRegion}, matches::Dict{Int, Vector{RefMatch}})
    covered = Set{Tuple{String, Int}}()
    for i in keys(matches)
        r = regions[i]
        r.whole && push!(covered, (r.location.file, r.unit_line))
    end
    return covered
end

# The reference-unit lookup miss, shared so a language with no library units allocates
# nothing.
const NO_REF_UNITS = Tuple{String, RefAnchor}[]

# Confirm one language's proposed pairs and record each project region's evidence. The LCS
# is the dominant cost, so it runs in parallel over the proposed pairs, written to a
# preallocated vector and read back in pair order, so the evidence is identical to the
# serial path at any thread count.
function library_pairs!(
        matches::Dict{Int, Vector{RefMatch}}, regions::Vector{ProjectRegion}, idxs::Vector{Int},
        pool::Vector{Tuple{String, RefAnchor}}, threshold::Float64, radius_factor::Float64
    )
    query = BandedSide(
        Dict{String, Int}[regions[i].histogram for i in idxs],
        Int[length(regions[i].sequence) for i in idxs],
    )
    search = BandedSide(
        Dict{String, Int}[a.histogram for (_, a) in pool],
        Int[a.size for (_, a) in pool],
    )
    pairs = banded_candidates(query, search, radius_factor, CROSS_BANDS)
    lengths = Vector{Int}(undef, length(pairs))
    parallel_map!(lengths) do k
        lcs_length(regions[idxs[pairs[k][1]]].sequence, pool[pairs[k][2]][2].sequence)
    end
    for k in eachindex(pairs)
        i = idxs[pairs[k][1]]
        library, anchor = pool[pairs[k][2]]
        regions[i].digest == anchor.hash && continue
        mine = min(length(regions[i].sequence), LCS_CAP)
        theirs = min(length(anchor.sequence), LCS_CAP)
        (mine == 0 || theirs == 0) && continue
        max(lengths[k] / mine, lengths[k] / theirs) >= threshold || continue
        push!(
            get!(() -> RefMatch[], matches, i),
            RefMatch(
                library, anchor.symbol, anchor.public, anchor.whole_unit,
                anchor.file, anchor.line, coverage_percent(lengths[k], regions[i].unit_size),
            )
        )
    end
    return matches
end
