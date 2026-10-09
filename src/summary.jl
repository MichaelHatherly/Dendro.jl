# The corpus summary pass. Every other reading in Dendro names a site and so names an
# edit; erosion and verbosity are ratios over a whole corpus, so they are report lines and
# never findings. They exist to be watched against their own trend, which is why nothing
# here carries a band, a percentile, or a route into the gate. The types the pass fills sit
# beside the other result types in `report.jl`.

# Physical lines in one source, the denominator verbosity divides by. A file whose last
# line carries no newline still ends on a line.
physical_lines(source::AbstractString) =
    isempty(source) ? 0 : count(==('\n'), source) + (endswith(source, '\n') ? 0 : 1)

# The complexity above which a callable's mass counts as eroded, from Radon by way of
# SlopCodeBench. It coincides with `cyclomatic`'s own warn edge of 11, so the cut is not a
# second opinion about complexity: erosion reports how much of a corpus's weight sits past
# that edge, where the rule reports which functions do.
const EROSION_COMPLEXITY = 10

# A callable's weight in the erosion ratio: complexity scaled by the square root of its
# length, so a long simple function and a short tangled one do not read alike. A nested
# callable is a unit of its own with its own mass, since `fold_unit` stops at one.
erosion_mass(unit::Unit, index::QueryIndex) = cyclomatic(unit, index) * sqrt(function_length(unit))

# Erosion over one corpus: the mass in callables past `EROSION_COMPLEXITY` over the mass in
# all of them, with the callable count beside it. A corpus with no callables has no mass to
# divide and reports zero rather than a NaN.
function erosion_score(files::Vector{ParsedFile})
    eroded = 0.0
    total = 0.0
    callables = 0
    for f in files
        for u in units(f.index)
            is_callable(u, f.index) || continue
            callables += 1
            m = erosion_mass(u, f.index)
            total += m
            cyclomatic(u, f.index) > EROSION_COMPLEXITY && (eroded += m)
        end
    end
    return (total > 0 ? eroded / total : 0.0), callables
end

# Record every line of one region as covered. A line two findings both reach is one line:
# verbosity asks how much of the corpus is implicated, never how many findings there are.
function cover!(covered::Set{Tuple{String, Int}}, file::String, from::Int, to::Int)
    for line in from:to
        push!(covered, (file, line))
    end
    return covered
end

# The metrics whose findings count toward verbosity. The clone passes read a region of the
# project's own source, which is what the ratio divides. `:library_duplicate` and
# `:reimplementation` are left out: one names source nobody can edit and the other reports a
# proposal rather than a region.
verbose_clone(f::Finding) = f.metric === RELATIONAL.duplicate || f.metric === RELATIONAL.near_duplicate

# Every `(file, line)` a declared flag rule or a clone finding covers.
#
# The flagged half reads the index rather than the findings: a diff-scoped scan reports only
# the files a change touched, and the score is about the corpus. Suppressed matches count
# too, for the same reason. A directive accepts a finding, which is a statement about what
# gets reported, where this measures what the source holds.
#
# Built-in flags are out of the numerator. SlopCodeBench counts an ast-grep rule set, which
# in Dendro is the pattern mechanism, and the built-in flag populations differ in shape;
# `empty_catch` would also double-count the shipped pack's `swallowed_error`. A scalar-kind
# pattern rule is out as well, since it counts matches per unit and names no region.
function covered_lines(
        files::Vector{ParsedFile}, clones::Vector{Finding}, specs::Vector{PatternSpec}
    )
    flags = Set{Symbol}(s.name for s in specs if s.kind === :flag)
    covered = Set{Tuple{String, Int}}()
    for f in files
        for name in keys(f.index.patterns)
            name in flags || continue
            for node in pattern_hits(f.index, name)
                cover!(covered, f.file, line_span(node)...)
            end
        end
    end
    for c in clones
        verbose_clone(c) || continue
        for loc in c.locations
            cover!(covered, loc.file, loc.line, loc.lastline)
        end
    end
    return covered
end

"""
    corpus_scores(files, clones, specs) -> CorpusScores

The summary scores over a whole parsed corpus. `clones` are the `:duplicate` and
`:near_duplicate` findings before any diff scoping, and `specs` the declared pattern rules,
which is how a flag rule is told from a scalar one.

Both scores read the whole corpus even when the scan is diff-scoped: a score answers what
the codebase looks like, which a diff cannot narrow.
"""
function corpus_scores(
        files::Vector{ParsedFile}, clones::Vector{Finding}, specs::Vector{PatternSpec}
    )
    er, callables = erosion_score(files)
    lines = sum(f -> physical_lines(f.source), files; init = 0)
    verbosity = lines > 0 ? length(covered_lines(files, clones, specs)) / lines : 0.0
    return CorpusScores(er, verbosity, lines, callables)
end
