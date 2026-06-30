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

fkey(f::Finding, root::AbstractString)::FloorKey =
    (f.metric, sort!([(relpath(realpath(loc.file), root), loc.unit) for loc in f.locations]))

# The base error floor as a multiset of keys. `git archive` the `since` revision of just
# `paths` into a tempdir, no worktree or index mutation, analyze that, and count each
# high-floor finding's key. The archive is scoped to `paths`, not the whole tree, so the
# base corpus matches HEAD's: a whole-tree archive would shift the baseline and clone
# corpus and manufacture deltas. An empty archive (paths new at `since`) leaves the count
# empty, so every HEAD finding reads as new. The ref is pre-checked, so a missing ref
# throws rather than silently degrading to the floor.
function base_floor_counts(roots::Vector{String}, since, root::AbstractString; rules, ignore, language)
    refspec = string(since, "^{commit}")
    verified = success(pipeline(`git -C $root rev-parse --verify --quiet $refspec`; stdout = devnull, stderr = devnull))
    verified || error("Dendro: `since` ref not found: $since")

    rels = [relpath(realpath(p), root) for p in roots]
    counts = Dict{FloorKey, Int}()
    mktempdir() do tmp
        # git archive errors when no path matches at `since` (paths new at base). The ref
        # is already validated, so an empty archive means an empty base set, every HEAD
        # finding new.
        archive = pipeline(`git -C $root archive $since -- $rels`; stderr = devnull)
        archived = success(pipeline(archive, pipeline(`tar -x -C $tmp`; stderr = devnull)))
        # macOS maps /tmp to /private/tmp; resolve the tempdir root so its relative paths
        # match HEAD's, or every base key misaligns and the ratchet calls everything new.
        troot = realpath(tmp)
        tpaths = String[joinpath(troot, r) for r in rels if ispath(joinpath(troot, r))]
        (archived && !isempty(tpaths)) || return
        for f in high_floor(active(analyze(tpaths; rules, ignore, language)))
            k = fkey(f, troot)
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
    out = Finding[]
    for f in head
        k = fkey(f, root)
        n = get(counts, k, 0)
        n > 0 ? (counts[k] = n - 1) : push!(out, f)
    end
    return Findings(out)
end

"""
    errors(paths; since=nothing, rules=BUILTIN_RULES, ignore=String[], language=nothing) -> Findings

The error-severity findings over `paths`: the deterministic floor, every finding at
the `:high` absolute band (high-band scalars and all flags), with inline
`dendro-ignore` directives applied first so a suppressed finding lifts the gate.

This is the gate companion to [`analyze`](@ref). `analyze` ranks by corpus percentile
for triage and so is never empty; `errors` reads only the fixed bands, so it is
satisfiable and stable, suitable for a CI gate. Assert `isempty(errors(path))` in a
test and every package's existing `Pkg.test()` gates on Dendro for free.

With `since`, a git ref, the result is the ratchet: the floor at the working tree
minus the floor at that ref. A finding the change introduced is reported; one that
predates the ref, even on a line the change touched, is not. This answers "did this
change introduce a violation", and supports incremental adoption on a codebase that is
not yet clean. A `since` that names no commit throws: a broken ref is CI
misconfiguration, never a silent fall-back to the floor.

`since` is distinct from [`analyze`](@ref)'s `base`. `base` is spatial, restricting
findings to changed lines for annotations; `since` is a finding-set difference, the
gate.

`rules`, `ignore`, and `language` pass through to [`analyze`](@ref).
"""
function errors(
        paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        since = nothing, rules = BUILTIN_RULES, ignore = String[], language = nothing
    )
    head = high_floor(active(analyze(paths; rules, ignore, language)))
    since === nothing && return head
    roots::Vector{String} = paths isa AbstractString ? [paths] : collect(paths)
    root = git_toplevel(roots)
    base = base_floor_counts(roots, since, root; rules, ignore, language)
    return ratchet(head, base, root)
end
