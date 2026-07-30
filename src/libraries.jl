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
# a bare path becomes a library named after its root. A string is one root rather than a
# list of roots, the reading a caller pointing at one directory means.
as_libraries(libraries)::Vector{Library} =
    Library[l isa Library ? l : Library(l) for l in (libraries isa AbstractString ? [libraries] : libraries)]

# Default near-miss cutoff for a cross-corpus match, `max(|LCS|/|a|, |LCS|/|r|)`. Either
# side being substantially covered is a match; the coverage score then says what it costs
# the project.
const DEFAULT_LIBRARY_THRESHOLD = 0.85

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
# near-miss features and are filled for whole units only: a block takes part in the exact
# join, where the hash is the whole verdict, and the near pass compares functions.
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
holds, `by_hash` for the exact join, and `units`, the indices of the whole-unit anchors
the near pass compares. Built by [`reference_index`](@ref), read and never scored.
"""
struct ReferenceIndex
    library::String
    by_hash::Dict{Tuple{Symbol, UInt64}, Vector{Int}}
    anchors::Vector{RefAnchor}
    units::Vector{Int}
end

# The lookup miss, shared so a project anchor that matches nothing allocates nothing.
const NO_ANCHORS = Int[]

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
    reference_index(library; min_size, profiles, exclude) -> ReferenceIndex

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
"""
function reference_index(
        library::Library; min_size::Integer,
        profiles::Dict{Symbol, LanguageProfile} = PROFILES, exclude::Set{String} = Set{String}()
    )
    paths = collect_corpus(library.roots, library.ignore, nothing; profiles)
    filter!(p -> !(realpath(p) in exclude), paths)
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
            sequence = preorder_hashes(st)
            histogram = histogram_of(st)
            for s in st
                floor = anchor_floor(s.node, f.index, min_size)
                (floor === nothing || s.size < floor) && continue
                whole = is_function(s.node, f.index)
                from, to = TreeSitter.byte_range(s.node)
                di = enclosing_def(topfns, from, to)
                push!(
                    anchors, RefAnchor(
                        f.language, s.hash, s.size,
                        whole ? sequence : UInt64[], whole ? histogram : Dict{String, Int}(),
                        whole, di == 0 ? "" : table.defs[di].name, di != 0 && public[di],
                        shown, Int(TreeSitter.start_point(s.node).row) + 1,
                    )
                )
                push!(get!(() -> Int[], by_hash, (f.language, s.hash)), length(anchors))
                whole && push!(units, length(anchors))
            end
        end
    end
    return ReferenceIndex(library.name, by_hash, anchors, units)
end

"""
    reference_indices(libraries, corpus; min_size, profiles) -> Vector{ReferenceIndex}

One [`ReferenceIndex`](@ref) per library, with `corpus`, the paths being scanned, excluded
from every one of them. Empty and free when no library is configured: absent `libraries`
there is nothing to switch on, only something to point at, so the feature is self-disabling
and an unconfigured scan pays nothing.
"""
function reference_indices(
        libraries::Vector{Library}, corpus::Vector{String};
        min_size::Integer, profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    isempty(libraries) && return ReferenceIndex[]
    exclude = Set{String}(realpath(p) for p in corpus)
    return ReferenceIndex[reference_index(l; min_size, profiles, exclude) for l in libraries]
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
function library_finding(
        metric::Symbol, site::Location, matches::Vector{RefMatch},
        directives::Vector{Directive}, gate_coverage::Integer
    )
    sort!(matches; by = m -> (!m.public, !m.whole_unit, -m.coverage, m.library, m.file, m.line))
    best = first(matches)
    band = best.public && best.whole_unit && best.coverage >= gate_coverage ? :high : :warn
    labelled = Location(site.file, site.line, site.unit, evidence_label(matches))
    sup = is_suppressed(directives, site.line, metric)
    return Finding(metric, [labelled], best.coverage, band, nothing, :flag, sup)
end

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
                push!(
                    findings, library_finding(
                        RELATIONAL.library_duplicate, Location(f.file, line, name),
                        hits[id], f.directives, gate_coverage
                    )
                )
            end
        end
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
