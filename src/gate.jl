# The quality gate. `analyze` answers triage, "where to look", and ranks by corpus
# percentile, so its result is never empty: the worst-N% always exists. A gate wants
# the opposite, a pass/fail signal that is satisfiable and stable. `errors` is that
# view, the error-severity findings, optionally narrowed to those a change introduced
# since a base ref.

# The error floor: findings at the `:high` absolute band. High-band scalars and every
# flag (flags are always `:high`). Percentile-only findings carry `:ok`/`:warn` and
# fall out, so the floor is satisfiable, never the worst-N% that always exists.
high_floor(findings) = Findings(filter(f -> f.absolute === :high, findings))

# A finding's location set keyed for cross-revision comparison: the metric paired with
# the sorted `(repo-relative file, unit)` of each location. `Finding` has no id; `line`
# shifts when unrelated edits move code; `unit` is "" for non-function flags and
# non-unique across overloads. The location set survives line drift and keeps overloads
# and clone members distinct. `root` anchors the file paths so HEAD and base align.
const FloorKey = Tuple{Symbol, Vector{Tuple{String, String}}}

fkey(f::Finding, root::AbstractString, rels::Dict{String, String})::FloorKey =
    (f.metric, sort!([(relative_to(rels, loc.file, root), loc.unit) for loc in f.locations]))

# The base error floor as a multiset of keys: analyze the corpus as it stood at `since` and
# count each high-floor finding's key. An empty base corpus (paths new at `since`) leaves
# the count empty, so every HEAD finding reads as new.
function base_floor_counts(roots::Vector{String}, since, root::AbstractString; config, rules, ignore, language)
    counts = Dict{FloorKey, Int}()
    with_base_corpus(roots, since, root, "since") do troot, tpaths
        isempty(tpaths) && return
        resolved = Dict{String, String}()
        for f in high_floor(active(analyze(tpaths; config, rules, ignore, language)))
            k = fkey(f, troot, resolved)
            counts[k] = get(counts, k, 0) + 1
        end
    end
    return counts
end

# The ratchet: HEAD high-floor findings not already accounted for in the base multiset.
# Walk HEAD in order, emitting one only when the base count for its key is exhausted, so
# a brand-new violation emits, a touched-but-not-worsened pre-existing one is matched and
# dropped, and an added duplicate of a pre-existing finding emits the excess. Scalars,
# flags, and clones key uniformly, no special case.
function ratchet(head::Findings, base_counts::Dict{FloorKey, Int}, root::AbstractString)
    counts = copy(base_counts)
    resolved = Dict{String, String}()
    out = Finding[]
    for f in head
        k = fkey(f, root, resolved)
        n = get(counts, k, 0)
        n > 0 ? (counts[k] = n - 1) : push!(out, f)
    end
    return Findings(out)
end

"""
    errors(paths; since=nothing, config=nothing, rules=nothing, ignore=String[], language=nothing, libraries=nothing) -> Findings

The error-severity findings over `paths`: the deterministic floor, every finding at
the `:high` absolute band (high-band scalars and all flags), with inline
`dendro-ignore` directives applied first so a suppressed finding lifts the gate.

This is the gate companion to [`analyze`](@ref). `analyze` ranks by corpus percentile
for triage and so is never empty; `errors` reads only the fixed bands, so it is
satisfiable and stable, suitable for a CI gate. Assert `isempty(errors(path))` in a
test and every package's existing `Pkg.test()` gates on Dendro for free.

Like [`analyze`](@ref), `errors` honors a [`Config`](@ref): it discovers one from the
repo `.dendro.toml` unless a `config` is passed, so a project that retunes a band or
toggles a rule sees the change in the gate, not only in `analyze`. The same config
scores the working tree and the `since` base, so a retuned band never reads as a
regression on its own.

With `since`, a git ref, the result is the ratchet: the floor at the working tree
minus the floor at that ref. A finding the change introduced is reported; one that
predates the ref, even on a line the change touched, is not. This answers "did this
change introduce a violation", and supports incremental adoption on a codebase that is
not yet clean. A `since` that names no commit throws: a broken ref is CI
misconfiguration, never a silent fall-back to the floor.

`since` is distinct from [`analyze`](@ref)'s `base`. `base` is spatial, restricting
findings to changed lines for annotations; `since` is a finding-set difference, the
gate.

`config`, `rules`, `ignore`, and `language` pass through to [`analyze`](@ref); `rules`
absent, the active set is the config's resolution of [`BUILTIN_RULES`](@ref) and the
enabled [`OPTIONAL_RULES`](@ref). `libraries` names the reference corpora to compare
against, folded into the resolved config so the working tree and the `since` base are
scored against the same ones.
"""
function errors(
        paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        since = nothing, config = nothing, rules = nothing, ignore = String[],
        language = nothing, libraries = nothing
    )
    roots::Vector{String} = paths isa AbstractString ? [paths] : collect(paths)
    discovered::Config = config === nothing ? discover_config(roots) : config
    cfg::Config = libraries === nothing ? discovered : override_config(discovered; libraries)
    head = high_floor(active(analyze(paths; config = cfg, rules, ignore, language)))
    since === nothing && return head
    root = git_toplevel(roots)
    base = base_floor_counts(roots, since, root; config = cfg, rules, ignore, language)
    return ratchet(head, base, root)
end
