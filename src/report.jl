# Findings and reporting. A Finding pairs a metric reading with the locations it
# covers and both scores, absolute (fixed band) and relative (corpus percentile).

"""
    Location

A code site: its `file` path, 1-based `line`, enclosing `unit` name ("" when no name node
is found), an optional `label`, what this site means to the finding carrying it, and the
`lastline` the site runs to.

`lastline` is the region a finding covers, which is what `corpus_scores` measures verbosity
over. It defaults to `line`, since most sites building a location report a point and have
no span to give. Diff scoping deliberately does not read it: `in_scope` and the gate's
`fkey` still test the first line alone, so widening a scope to a whole span stays a
separate decision from recording one.

A label is what lets a finding name an edit rather than only score one. `:scattered` counts
how many communities a file's units are pulled into; the label on each location says which
file it is pulled toward, which is the move. `:split_audience` and `:hub` label each
representative with the files consuming its audience, which is the split. Without them a
reader has to rebuild the corpus graph to recover what the pass already computed.

A label is evidence, not identity: the gate's `fkey` reads `file` and `unit` alone, so
labelling a site never moves a ratchet key and never re-reports a finding. Where the label
*is* the identity, `:dependency_cycle`'s choice of which edge to cut, it goes in `unit`
instead and does enter the key.
"""
struct Location
    file::String
    line::Int
    unit::String
    label::String
    lastline::Int
end
Location(file, line, unit, label) = Location(file, line, unit, label, line)
Location(file, line, unit) = Location(file, line, unit, "", line)

"""
    Finding

One reported issue over one or more locations. Per-file metrics fire at a single
location; relational metrics like `:duplicate` span several.

- `metric`: which metric fired (`:cyclomatic`, `:empty_catch`, `:duplicate`, ...).
- `locations`: every site the finding covers, at least one.
- `value`: the scalar reading, the member count for `:duplicate`, or `nothing`.
- `absolute`: `:ok`/`:warn`/`:high` band, always `:high` for flags.
- `percentile`: corpus rank in `[0, 1]`, or `nothing` when no corpus sample ranks against it.
- `kind`: `:scalar` or `:flag`.
- `suppressed`: whether an inline directive accepted this finding.
"""
struct Finding
    metric::Symbol
    locations::Vector{Location}
    value::Union{Int, Nothing}
    absolute::Symbol
    percentile::Union{Float64, Nothing}
    kind::Symbol
    suppressed::Bool
end

# Single-location finding, the shape every per-file metric produces. Its ten
# parameters mirror the struct's seven fields with the location split into file,
# line, unit, and last line, so the count tracks the struct, not a wide interface.
# dendro-ignore: parameter_count
Finding(file, line, lastline, unit, metric, value, absolute, percentile, kind, suppressed) =
    Finding(
    metric, [Location(file, line, unit, "", lastline)], value, absolute, percentile, kind, suppressed
)

"""
    Scan

The fixed context for analysing one file: its `index` of identified nodes and the
`file` path, the active `rules`, the optional `baseline` and `cut` percentile for
relative scoring, the optional `within` line ranges that restrict findings to a
diff, and the `directives` parsed from the source that suppress accepted findings.
"""
struct Scan
    index::QueryIndex
    file::String
    rules::Vector{Rule}
    baseline::Union{Baseline, Nothing}
    cut::Float64
    within::Union{Vector{UnitRange{Int}}, Nothing}
    directives::Vector{Directive}
    # Whether each `(language, metric)`'s distribution supports a rank, resolved once per
    # scan by `percentile_guard`. A metric that is zero for most units has a degenerate
    # rank, and reading it would report a function for holding a single occurrence.
    guard::Dict{Tuple{Symbol, Symbol}, Bool}
end

# dendro-ignore: parameter_count -- one keyword per piece of scan context, mirroring the struct
function Scan(
        index, file; rules = BUILTIN_RULES, baseline = nothing, cut = 0.95,
        within = nothing, directives = Directive[],
        guard = Dict{Tuple{Symbol, Symbol}, Bool}()
    )
    return Scan(index, String(file), rules, baseline, Float64(cut), within, directives, guard)
end

# Whether this scan reads `metric`'s corpus rank at all: only with a baseline to rank
# against, and only where that baseline's distribution supports a rank. Absent an entry the
# guard defaults to reading it, which is what keeps a `Scan` built without one behaving as
# it did before the guard existed.
ranks(scan::Scan, metric::Symbol) =
    scan.baseline !== nothing && get(scan.guard, (scan.index.language, metric), true)

# Whether a line span (or single line) is reported, given the scan's diff scope.
in_scope(scan::Scan, a::Int, b::Int) = scan.within === nothing || intersects(scan.within, a, b)
in_scope(scan::Scan, line::Int) = scan.within === nothing || inrange(scan.within, line)

# Scalar findings for one function unit, one per scalar rule that fires.
function unit_findings!(out, scan::Scan, unit::Unit)
    name = unit_name(unit, scan.index)
    for r in rules_of_kind(scan.rules, :scalar)
        applies(r, unit, scan.index) || continue
        value = r.fn(unit, scan.index)::Int
        band = severity(value, something(r.band))
        pct = ranks(scan, r.name) ?
            percentile(scan.baseline, scan.index.language, r.name, value) : nothing
        outlier = pct !== nothing && pct >= scan.cut
        if band != :ok || outlier
            sup = is_suppressed(scan.directives, unit.firstline, r.name)
            push!(
                out,
                Finding(scan.file, unit.firstline, unit.lastline, name, r.name, value, band, pct, :scalar, sup)
            )
        end
    end
    return out
end

# Flag findings for a set of nodes, all reported with the same metric, each carrying
# `severity` as its absolute band. A node that is itself a function unit is labelled with
# its name; other nodes are not.
#
# Every built-in flag takes the `:high` default, which is what puts it in the `errors`
# floor. A user-authored pattern rule may be `:warn` instead, so declaring one cannot make
# the gate unsatisfiable on a codebase where it fires.
function flag_findings!(out, scan::Scan, nodes, metric::Symbol, severity::Symbol = :high)
    for node in nodes
        line, lastline = line_span(node)
        in_scope(scan, line) || continue
        name = is_function(node, scan.index) ?
            unit_name(node, scan.index) : ""
        sup = is_suppressed(scan.directives, line, metric)
        push!(
            out,
            Finding(scan.file, line, lastline, name, metric, nothing, severity, nothing, :flag, sup)
        )
    end
    return out
end

"""
    findings_for(scan) -> Vector{Finding}

Collect findings for the scan's indexed tree. Scalar metrics fire when they breach
their absolute band or, given a baseline, land at or above the cut percentile. Flag
metrics fire on presence. A diff-scoped `scan` reports only units overlapping a
changed range and flags on a changed line.
"""
function findings_for(scan::Scan)
    out = Finding[]
    for unit in units(scan.index)
        in_scope(scan, unit.firstline, unit.lastline) || continue
        unit_findings!(out, scan, unit)
    end
    for r in rules_of_kind(scan.rules, :flag)
        flag_findings!(out, scan, r.fn(scan.index)::Vector{TreeSitter.Node}, r.name, r.severity)
    end
    return out
end

"""
    CorpusScores

Two ratios over one corpus, with the sizes they were divided by.

- `erosion`: the share of callable mass sitting in complex functions.
- `verbosity`: the share of source lines a flag rule or a clone finding covers.
- `lines`: physical source lines across the corpus, verbosity's denominator.
- `callables`: how many definitions erosion was computed over.

A default-constructed value is the empty corpus, every score zero. `lines` is what tells
that apart from a scored corpus, since a corpus holding source always has lines.

Neither ratio is a [`Finding`](@ref) and neither reaches the gate. A ratio over a corpus
names no site, so it names no edit; see `corpus_scores`.
"""
struct CorpusScores
    erosion::Float64
    verbosity::Float64
    lines::Int
    callables::Int
end
CorpusScores() = CorpusScores(0.0, 0.0, 0, 0)

"""
    GeneratedFile

One file a scan read the head of and did not parse: its `path`, and the `signature` that
named it as generated or bundled.

A scan carries these rather than dropping them, the same stance a suppressed finding takes.
Lose half a corpus quietly and the report reads as a clean codebase, so the count and the
signatures behind it print after the findings.
"""
struct GeneratedFile
    path::String
    signature::String
end

"""
    LineDelta

How many lines a change added and removed, libgit2's own tally over the diff. A fact about
the size of a change rather than a judgement about it, so like [`CorpusScores`](@ref) it is
reported and never gated.
"""
struct LineDelta
    added::Int
    removed::Int
end
LineDelta() = LineDelta(0, 0)

"""
    ScanSummary

What one scan measured about its corpus as a whole: the scores `now`, the same scores at
the `base` ref, and the line `delta` between the two. Without a `base` ref the last two are
empty, which is what a report reads to decide whether it has a comparison to print.
"""
struct ScanSummary
    now::CorpusScores
    base::CorpusScores
    delta::LineDelta
end
ScanSummary() = ScanSummary(CorpusScores(), CorpusScores(), LineDelta())
ScanSummary(now::CorpusScores) = ScanSummary(now, CorpusScores(), LineDelta())

# Whether this summary was measured against a base ref. An empty base corpus has no lines
# and a scored one always does, so the denominator is the signal rather than a fourth field
# restating what the first three already say.
has_base(s::ScanSummary) = s.base.lines > 0

"""
    Findings <: AbstractVector{Finding}

The result of [`analyze`](@ref): the findings it produced, printed as a report.
Behaves as an `AbstractVector{Finding}`, so it iterates, filters, and indexes like
any vector of [`Finding`](@ref)s.
"""
struct Findings <: AbstractVector{Finding}
    items::Vector{Finding}
    # Declared pattern rules that matched nothing anywhere in the corpus. A rule whose
    # query compiles cleanly but names a shape the grammar never produces reports nothing
    # and reads as clean code, which is the one failure neither tree-sitter's own
    # validation nor a review catches. Carried on the result rather than warned, since it
    # describes the run rather than diagnosing a file.
    unmatched::Vector{Symbol}
    # What the scan measured about the corpus as a whole. Empty unless `analyze` built it:
    # `high_floor` and the ratchet rebuild a `Findings` from a finding set alone, and a
    # corpus ratio is not a finding set to difference.
    summary::ScanSummary
    # The files the parse boundary read the head of and turned away as generated. Empty
    # unless `analyze` built it, for the reason `summary` is.
    generated::Vector{GeneratedFile}
end
Findings(items::Vector{Finding}, unmatched::Vector{Symbol}, summary::ScanSummary) =
    Findings(items, unmatched, summary, GeneratedFile[])
Findings(items::Vector{Finding}, unmatched::Vector{Symbol}) = Findings(items, unmatched, ScanSummary())
Findings(items::Vector{Finding}) = Findings(items, Symbol[], ScanSummary())

Base.size(fs::Findings) = size(fs.items)
Base.getindex(fs::Findings, i::Int) = fs.items[i]
Base.IndexStyle(::Type{Findings}) = IndexLinear()

"""
    active(findings) -> Findings

The findings not suppressed by an inline directive. Use this for gating.

Everything the scan measured about the run rather than about a file, the unmatched rules,
the corpus summary and the files excluded as generated, carries over: a directive accepts
one finding and says nothing about any of them.
"""
active(findings::Findings) = Findings(
    filter(f -> !f.suppressed, findings), findings.unmatched, findings.summary,
    findings.generated
)

# A location's label as it renders, set off from the unit name so the two read apart. Empty
# for a site whose finding attached no meaning to it, which is every per-file metric.
note(loc::Location) = isempty(loc.label) ? "" : string("  [", loc.label, "]")

# The score column shared by every renderer: the absolute band, plus the corpus
# percentile when one ranks the value.
function score_suffix(f::Finding)
    rel = f.percentile === nothing ? "" : string("; p", round(Int, f.percentile * 100))
    return string("(", f.absolute, rel, ")")
end

# A summary ratio to two decimal places. Printf is not a dependency, and both ratios run
# from zero to one, so two digits are the whole reading rather than a format to negotiate.
function two_places(x::Float64)
    hundredths = round(Int, abs(x) * 100)
    return string(x < 0 ? "-" : "", hundredths ÷ 100, ".", lpad(hundredths % 100, 2, '0'))
end

# The width the summary labels share, so the values line up under each other.
const SUMMARY_LABEL = 9

# One summary score, and with a base ref what it was there and which way it moved. The
# movement is signed both ways: a report read at a glance has to say which direction is
# which without the reader subtracting.
function score_line(io::IO, label::AbstractString, now::Float64, base::Float64, compare::Bool)
    moved = now - base
    sign = moved < 0 ? "" : "+"
    against = compare ? string("  (base ", two_places(base), ", ", sign, two_places(moved), ")") : ""
    println(io, rpad(label, SUMMARY_LABEL), " ", two_places(now), against)
    return nothing
end

# How large the change was, beside what the scores say it made worse. The size is a fact
# about the diff rather than a judgement on it, so it prints as a count and carries no band.
function delta_line(io::IO, d::LineDelta)
    net = d.added - d.removed
    println(
        io, rpad("lines", SUMMARY_LABEL), " +", d.added, " -", d.removed,
        "  (net ", net < 0 ? "" : "+", net, ")"
    )
    return nothing
end

# What the parse boundary turned away, printed with the count and the signatures behind it.
# A scan that lost half its corpus to a vendored bundle would otherwise read as a clean
# codebase, the same reason the suppressed count prints.
function show_generated(io::IO, generated::Vector{GeneratedFile})
    isempty(generated) && return nothing
    println(
        io, length(generated), " file(s) excluded as generated (",
        join(unique(g.signature for g in generated), ", "), ")"
    )
    return nothing
end

# The corpus scores, printed after every finding. A summary with no lines was never
# measured: `high_floor` and the ratchet rebuild a `Findings` from findings alone, and the
# gate has nothing to say about a ratio.
function show_summary(io::IO, s::ScanSummary)
    s.now.lines > 0 || return nothing
    compare = has_base(s)
    score_line(io, "erosion", s.now.erosion, s.base.erosion, compare)
    score_line(io, "verbosity", s.now.verbosity, s.base.verbosity, compare)
    compare && delta_line(io, s.delta)
    return nothing
end

# The REPL display for the `Findings` `analyze` returns. Each finding prints as
# `file:line  unit  metric value (scores)`, with an `also at` line per extra
# location, and a trailing count of findings suppressed by directives so
# suppressions stay visible rather than silently dropped.
function Base.show(io::IO, ::MIME"text/plain", findings::Findings)
    suppressed = shown = 0
    for f in findings
        if f.suppressed
            suppressed += 1
            continue
        end
        anchor = first(f.locations)
        loc = string(anchor.file, ":", anchor.line)
        label = isempty(anchor.unit) ? "" : string("  ", anchor.unit)
        val = f.value === nothing ? "" : string(" ", f.value)
        println(io, loc, label, note(anchor), "  ", f.metric, val, " ", score_suffix(f))
        for extra in Iterators.drop(f.locations, 1)
            tag = isempty(extra.unit) ? "" : string("  ", extra.unit)
            println(io, "    also at ", extra.file, ":", extra.line, tag, note(extra))
        end
        shown += 1
    end
    shown == 0 && suppressed == 0 && println(io, "No findings.")
    suppressed > 0 && println(io, suppressed, " finding(s) suppressed by directives")
    isempty(findings.unmatched) ||
        println(io, "warning: pattern rule(s) matched nothing: ", join(findings.unmatched, ", "))
    show_generated(io, findings.generated)
    show_summary(io, findings.summary)
    return nothing
end

# GitHub Actions workflow commands escape `%`, `\r`, `\n` in a message, and
# additionally `:` and `,` in a property value, so neither breaks the line.
escape_data(s::AbstractString) = replace(s, "%" => "%25", "\r" => "%0D", "\n" => "%0A")
escape_prop(s::AbstractString) = replace(escape_data(s), ":" => "%3A", "," => "%2C")

# The single-line message for one finding: `unit: metric value (scores)`, with a
# trailing `; also at file:line` per extra location so a multi-site finding names
# its other members where annotations are line-anchored.
function annotation_message(f::Finding)
    anchor = first(f.locations)
    prefix = isempty(anchor.unit) ? "" : string(anchor.unit, ": ")
    val = f.value === nothing ? "" : string(" ", f.value)
    msg = string(prefix, f.metric, val, " ", score_suffix(f), note(anchor))
    for extra in Iterators.drop(f.locations, 1)
        msg = string(msg, "; also at ", extra.file, ":", extra.line, note(extra))
    end
    return msg
end

"""
    github_annotations(io, findings)
    github_annotations(findings)

Write `findings` as GitHub Actions workflow commands, one `::error`/`::warning`
line per finding, anchored at its first location. GitHub records each as a
pull-request check annotation; it renders inline on the diff when the anchored line
is part of the change, otherwise in the run's Checks tab. Pair this with `analyze`'s
`base` to scope findings to the functions a change touched. Suppressed findings are
omitted. High-band findings map to `::error`, the rest to `::warning`.
"""
function github_annotations(io::IO, findings::Findings)
    for f in findings
        f.suppressed && continue
        anchor = first(f.locations)
        level = f.absolute === :high ? "error" : "warning"
        title = string("Dendro: ", f.metric)
        println(
            io, "::", level, " file=", escape_prop(anchor.file),
            ",line=", anchor.line, ",title=", escape_prop(title),
            "::", escape_data(annotation_message(f))
        )
    end
    return nothing
end

github_annotations(findings::Findings) = github_annotations(stdout, findings)
