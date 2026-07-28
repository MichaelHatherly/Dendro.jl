# Findings and reporting. A Finding pairs a metric reading with the locations it
# covers and both scores, absolute (fixed band) and relative (corpus percentile).

"""
    Location

A code site: its `file` path, 1-based `line`, enclosing `unit` name ("" when no name node
is found), and an optional `label`, what this site means to the finding carrying it.

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
end
Location(file, line, unit) = Location(file, line, unit, "")

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

# Single-location finding, the shape every per-file metric produces. Its nine
# parameters mirror the struct's seven fields with the location split into file,
# line, and unit, so the count tracks the struct, not a wide interface.
# dendro-ignore: parameter_count
Finding(file, line, unit, metric, value, absolute, percentile, kind, suppressed) =
    Finding(metric, [Location(file, line, unit)], value, absolute, percentile, kind, suppressed)

# The defining name tagged on `node`'s binder, a sibling outside its subtree, or "".
# An anonymous callable bound to a name (a JS arrow `const f = () => ...`) carries its
# name on the enclosing binder, so a unit holding no name of its own takes the binder's.
function binder_def_name(node::TreeSitter.Node, index::QueryIndex)
    p = TreeSitter.parent(node)
    TreeSitter.is_null(p) && return ""
    for c in TreeSitter.children(p)
        c in index.def_name && return String(strip(TreeSitter.slice(index.source, c)))
    end
    return ""
end

# Label a function node by its name, or "" when no name node is found. A qualified
# definition tags its final component as `def_name`; prefer that over the first
# `@name`, which for `Module.method` is the module qualifier. A bound anonymous
# callable takes the name from its enclosing binder when it holds none of its own.
function unit_name(node::TreeSitter.Node, index::QueryIndex)
    name = Ref("")
    def = Ref("")
    TreeSitter.traverse(node) do n, enter
        if enter
            isempty(name[]) && n in index.name &&
                (name[] = String(strip(TreeSitter.slice(index.source, n))))
            isempty(def[]) && n in index.def_name &&
                (def[] = String(strip(TreeSitter.slice(index.source, n))))
        end
        nothing
    end
    isempty(def[]) || return def[]
    binder = binder_def_name(node, index)
    return isempty(binder) ? name[] : binder
end

unit_name(unit::FunctionUnit, index::QueryIndex) = unit_name(unit.node, index)

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
end

Scan(index, file; rules = BUILTIN_RULES, baseline = nothing, cut = 0.95, within = nothing, directives = Directive[]) =
    Scan(index, String(file), rules, baseline, Float64(cut), within, directives)

# Whether a line span (or single line) is reported, given the scan's diff scope.
in_scope(scan::Scan, a::Int, b::Int) = scan.within === nothing || intersects(scan.within, a, b)
in_scope(scan::Scan, line::Int) = scan.within === nothing || inrange(scan.within, line)

# Scalar findings for one function unit, one per scalar rule that fires.
function unit_findings!(out, scan::Scan, unit::FunctionUnit)
    name = unit_name(unit, scan.index)
    for r in rules_of_kind(scan.rules, :scalar)
        value = r.fn(unit, scan.index)::Int
        band = severity(value, something(r.band))
        pct = scan.baseline === nothing ? nothing :
            percentile(scan.baseline, scan.index.language, r.name, value)
        outlier = pct !== nothing && pct >= scan.cut
        if band != :ok || outlier
            sup = is_suppressed(scan.directives, unit.firstline, r.name)
            push!(out, Finding(scan.file, unit.firstline, name, r.name, value, band, pct, :scalar, sup))
        end
    end
    return out
end

# Flag findings for a set of nodes, all reported with the same metric. A node
# that is itself a function unit is labelled with its name; other nodes are not.
function flag_findings!(out, scan::Scan, nodes, metric::Symbol)
    for node in nodes
        line = line_of(node)
        in_scope(scan, line) || continue
        name = is_function(node, scan.index) ?
            unit_name(node, scan.index) : ""
        sup = is_suppressed(scan.directives, line, metric)
        push!(out, Finding(scan.file, line, name, metric, nothing, :high, nothing, :flag, sup))
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
    for unit in functions(scan.index)
        in_scope(scan, unit.firstline, unit.lastline) || continue
        unit_findings!(out, scan, unit)
    end
    for r in rules_of_kind(scan.rules, :flag)
        flag_findings!(out, scan, r.fn(scan.index)::Vector{TreeSitter.Node}, r.name)
    end
    return out
end

# The two scores one value carries: its severity against the fixed `band`, and its
# percentile among `counts`, the values of everything scored alongside it. The percentile
# is `nothing` unless `enough` of them were scored to rank against, so a thin corpus is
# read on the absolute band alone. Every corpus-relational pass reads a value this way,
# whatever it scores, a file, a directory pair, or a cycle.
function two_scores(value::Int, counts::Vector{Int}, band::Tuple{Int, Int}, enough::Bool)
    absolute = severity(value, band)
    pct = enough ? searchsortedlast(counts, value) / length(counts) : nothing
    return absolute, pct
end

# Whether a reading is reported: either score trips, the absolute band or the corpus rank.
# Both halves are kept, since absolute alone misses an outlier in a uniformly weak corpus
# and the rank alone calls that corpus fine.
fires(absolute::Symbol, pct::Union{Float64, Nothing}, cut::Real) =
    absolute !== :ok || (pct !== nothing && pct >= cut)

"""
    scored_findings(metric, scored, band, cut, min_files; min_reported=1) -> Vector{Finding}

One `metric` finding per entry of `scored`, the emission the file-level corpus passes
share. Each entry pairs a file with its value and the locations to report it at, the
first of which is the site a `dendro-ignore` covers. A finding is emitted when the value
breaches the absolute `band` or lands at or above the `cut` percentile of the scored
values, the two-score model; the percentile is read only once the corpus holds
`min_files` scored entries, and is `nothing` below that.

`min_reported` is the smallest value that names something to act on. Entries below it
stay in the scored population, so they count toward the percentile of the entries above,
but never emit. Findings come back sorted by descending value, then file and line.

An entry is keyed by its `ParsedFile` because the suppression directive is read off it, and
that is what bounds this to the passes scoring a file. `:misplaced` scores a unit,
`:back_edge` a directory pair, `:dependency_cycle` a cyclic component, and `:hub` a graph
node; each reads its directives out of a path-keyed dict instead, and `:hub` resolves its
locations only for the entries that fire, which this shape cannot express because it takes
them upfront. Those four emit directly and share the part that is genuinely common, the
band-and-percentile reading through `two_scores` and `fires`. Widening this to cover them
would take a subject type parameter and a lazy-location callback to save six lines each,
which is the wrong trade.
"""
function scored_findings(
        metric::Symbol, scored::Vector{Tuple{ParsedFile, Int, Vector{Location}}},
        band::Tuple{Int, Int}, cut::Real, min_files::Integer; min_reported::Int = 1
    )
    findings = Finding[]
    counts = sort([s[2] for s in scored])
    enough = length(scored) >= min_files
    for (f, value, locations) in scored
        value >= min_reported || continue
        absolute, pct = two_scores(value, counts, band, enough)
        fires(absolute, pct, cut) || continue
        sup = is_suppressed(f.directives, locations[1].line, metric)
        push!(findings, Finding(metric, locations, value, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end

"""
    Findings <: AbstractVector{Finding}

The result of [`analyze`](@ref): the findings it produced, printed as a report.
Behaves as an `AbstractVector{Finding}`, so it iterates, filters, and indexes like
any vector of [`Finding`](@ref)s.
"""
struct Findings <: AbstractVector{Finding}
    items::Vector{Finding}
end

Base.size(fs::Findings) = size(fs.items)
Base.getindex(fs::Findings, i::Int) = fs.items[i]
Base.IndexStyle(::Type{Findings}) = IndexLinear()

"""
    active(findings) -> Findings

The findings not suppressed by an inline directive. Use this for gating.
"""
active(findings) = Findings(filter(f -> !f.suppressed, findings))

# The score column shared by every renderer: the absolute band, plus the corpus
# percentile when one ranks the value.
# A location's label as it renders, set off from the unit name so the two read apart. Empty
# for a site whose finding attached no meaning to it, which is every per-file metric.
note(loc::Location) = isempty(loc.label) ? "" : string("  [", loc.label, "]")

function score_suffix(f::Finding)
    rel = f.percentile === nothing ? "" : string("; p", round(Int, f.percentile * 100))
    return string("(", f.absolute, rel, ")")
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
