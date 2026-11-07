# The quality gate. `analyze` answers triage, "where to look", and ranks by corpus
# percentile, so its result is never empty: the worst-N% always exists. A gate wants
# the opposite, a pass/fail signal that is satisfiable and stable. `errors` is that
# view, the error-severity findings, optionally narrowed to those a change introduced
# since a base ref.

# The error floor: findings at the `:high` absolute band. High-band scalars and every
# flag (flags are always `:high`). Percentile-only findings carry `:ok`/`:warn` and
# fall out, so the floor is satisfiable, never the worst-N% that always exists.
high_floor(findings) = Findings(filter(f -> f.absolute === :high, findings))

# A finding keyed for cross-revision comparison. `Finding` has no id; `line` shifts when
# unrelated edits move code; `unit` is "" for non-function flags and non-unique across
# overloads. So the key is the metric, the sorted `(repo-relative file, unit)` of every
# location, the finding's home, and its value. `root` anchors the file paths so HEAD and
# base align. Which of those a match reads depends on what the locations are, `FLOOR_HOMES`.
const FloorKey = @NamedTuple{
    metric::Symbol, sites::Vector{Tuple{String, String}}, home::Tuple{String, String}, value::Float64,
}

# How an aggregate finding is identified, by metric. Its locations are members or
# representatives standing for the finding, not the finding itself, so they are evidence.
# A clone's members are interchangeable sites of one claim, so a clone that lost members
# is the one it shrank from (`:members`). A finding about a file, a directory or one
# owning unit is that home, and is new only when its value rises (`:file`, `:directory`,
# `:unit`, the home read off the first location). Every other finding keys on its exact
# site set: one location for a per-unit metric, and for `:back_edge`, `:dependency_cycle`
# and `:divisible_package` the sites are the proposed edit, so a site gained is worsening.
const FLOOR_HOMES = Dict{Symbol, Symbol}(
    RELATIONAL.duplicate => :members,
    RELATIONAL.near_duplicate => :members,
    RELATIONAL.reimplementation => :members,
    RELATIONAL.low_cohesion => :file,
    RELATIONAL.scattered => :file,
    RELATIONAL.split_audience => :file,
    RELATIONAL.hub => :file,
    RELATIONAL.incoherent_package => :directory,
    RELATIONAL.misplaced => :unit,
    RELATIONAL.distant_definition => :unit,
)

floor_home(metric::Symbol) = get(FLOOR_HOMES, metric, :sites)

function fkey(f::Finding, root::AbstractString, rels::Dict{String, String})::FloorKey
    sites = sort!([(relative_to(rels, loc.file, root), loc.unit) for loc in f.locations])
    mode = floor_home(f.metric)
    first_file = isempty(f.locations) ? "" : relative_to(rels, first(f.locations).file, root)
    home = mode === :file ? (first_file, "") :
        mode === :directory ? (dirname(first_file), "") :
        mode === :unit ? (first_file, first(f.locations).unit) : ("", "")
    value = f.value === nothing ? 0.0 : Float64(f.value)
    return (; metric = f.metric, sites, home, value)
end

# Every finding's key, in order, the base side of the ratchet.
function floor_keys(findings::Findings, root::AbstractString, rels::Dict{String, String} = Dict{String, String}())
    return FloorKey[fkey(f, root, rels) for f in findings]
end

# Whether base finding `b` accounts for HEAD finding `k`. `exact` asks for the same site set
# (and, for a home-identified finding, a value that did not rise); otherwise `k` may be what
# `b` shrank to, or `b`'s home at a value no higher.
function accounts_for(b::FloorKey, k::FloorKey, exact::Bool)
    b.metric === k.metric || return false
    mode = floor_home(k.metric)
    homed = mode === :file || mode === :directory || mode === :unit
    if homed
        (b.home == k.home && k.value <= b.value) || return false
    end
    exact && return b.sites == k.sites
    mode === :members && return issubset(k.sites, b.sites)
    return homed
end

# The base floor as keys: analyze the corpus as it stood at `since` and key each high-floor
# finding. An empty base corpus (paths new at `since`) leaves no keys, so every HEAD
# finding reads as new.
function base_floor_keys(roots::Vector{String}, since, root::AbstractString; config, rules, ignore, language)
    keys = FloorKey[]
    with_base_corpus(roots, since, root, "since") do troot, tpaths
        isempty(tpaths) && return
        append!(keys, floor_keys(high_floor(active(analyze(tpaths; config, rules, ignore, language))), troot))
    end
    return keys
end

# The ratchet: HEAD high-floor findings no base finding accounts for. Each base finding
# accounts for one HEAD finding, so a brand-new violation emits, a touched-but-not-worsened
# pre-existing one is matched and dropped, and an added duplicate of a pre-existing finding
# emits the excess. Exact matches are taken first, so a shrunk or re-represented finding
# never spends the base an unchanged one needs; among several candidates the one with the
# fewest sites wins, then base order, so the match never depends on iteration order.
function ratchet(head::Findings, base::Vector{FloorKey}, root::AbstractString)
    used = falses(length(base))
    resolved = Dict{String, String}()
    keys = FloorKey[fkey(f, root, resolved) for f in head]
    matched = falses(length(keys))
    for exact in (true, false), (i, k) in enumerate(keys)
        matched[i] && continue
        best = 0
        for (j, b) in enumerate(base)
            (used[j] || !accounts_for(b, k, exact)) && continue
            (best == 0 || length(b.sites) < length(base[best].sites)) && (best = j)
        end
        best == 0 && continue
        used[best] = true
        matched[i] = true
    end
    return Findings(Finding[f for (f, m) in zip(head, matched) if !m])
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
    base = base_floor_keys(roots, since, root; config = cfg, rules, ignore, language)
    return ratchet(head, base, root)
end
