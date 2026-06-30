# Tunable thresholds as data. Every band Dendro flags against is an opinion the
# bands philosophy calls retunable; this layer lets a project retune them from a
# `.dendro.toml` without editing source. The corpus floors and model internals stay
# fixed, out of the bargain: they are mechanism, not policy.
#
# Configuration is a cascade merged key by key, last wins:
#
#     built-in defaults  ->  ~/.config/dendro/config.toml  ->  repo .dendro.toml  ->  analyze kwargs
#
# `discover_config` accumulates each layer's overrides and builds one immutable
# `Config`; `analyze` reads it, resolving an explicit `cut` kwarg over the file value
# without mutating the struct. Discovery is source precedence, never spatial scoping:
# one corpus, one baseline, one set of bands per run, since the corpus-relative score
# is global and per-subtree bands would be incoherent with it.

# The percentile cutoff a corpus-relative metric flags above, absent a `.dendro.toml`.
const DEFAULT_CUT = 0.95

# The four relational metrics whose band a `[bands]` key may set. The rest of a
# `[bands]` table names scalar rules.
const RELATIONAL_BANDS = (:unnatural, :low_cohesion, :scattered, :misplaced)

"""
    Config

Resolved tuning thresholds for one analysis, built by `discover_config` from the
built-in defaults and a `.dendro.toml`. `cut` is the percentile cutoff; `bands`
overrides scalar rule `(warn, high)` tuples by metric name; the four relational fields
override the relational bands; `rules` toggles a rule on or off by name; `min_size`,
`threshold`, and `radius_factor` are the clone-detection thresholds. Immutable: pass
one to [`analyze`](@ref) with `config =` to skip file discovery.
"""
struct Config
    cut::Float64
    bands::Dict{Symbol, Tuple{Int, Int}}
    unnatural::Tuple{Int, Int}
    low_cohesion::Tuple{Int, Int}
    scattered::Tuple{Int, Int}
    misplaced::Tuple{Int, Int}
    rules::Dict{Symbol, Bool}
    min_size::Int
    threshold::Float64
    radius_factor::Float64
end

# The scalar metric names a `[bands]` key may set: every scalar rule, built-in or
# optional. Flag rules carry no band, so naming one under `[bands]` is an error.
scalar_metric_names() = Set(r.name for r in [BUILTIN_RULES; OPTIONAL_RULES] if r.kind === :scalar)

# Every rule name a `[rules]` key may toggle, built-in or optional, of either kind.
rule_names() = Set(r.name for r in [BUILTIN_RULES; OPTIONAL_RULES])

"""
    resolve_rules(config) -> Vector{Rule}

The active rule set the config selects: [`BUILTIN_RULES`](@ref) minus the names
`config` disables, plus the [`OPTIONAL_RULES`](@ref) it enables, each scalar rule's
band replaced by a `config` override when one is set. The default carries the same
rules `analyze` used before configuration.
"""
function resolve_rules(config::Config)
    out = Rule[]
    for (rules, default_on) in ((BUILTIN_RULES, true), (OPTIONAL_RULES, false))
        for r in rules
            get(config.rules, r.name, default_on) && push!(out, reband(r, config))
        end
    end
    return out
end

# A rule with its band replaced by the config override, when the metric carries one.
reband(r::Rule, config::Config) =
    haskey(config.bands, r.name) ? Rule(r.name, r.kind, config.bands[r.name], r.fn) : r

# Coerce a TOML `[warn, high]` array into the band tuple `severity` reads, erroring on
# a malformed value so a typo'd band fails loud rather than scoring against garbage.
function band_tuple(value, name, source)
    value isa AbstractVector && length(value) == 2 && all(v -> v isa Integer, value) ||
        error("Dendro: band `$name` in $source must be two integers [warn, high], got $value")
    return (Int(value[1]), Int(value[2]))
end

# The override dicts an analysis accumulates across config layers: scalar bands,
# relational bands, and rule toggles. Bundled so `apply_toml!` carries one accumulator
# rather than three, keeping its own metrics out of the warn band.
overrides() = (
    bands = Dict{Symbol, Tuple{Int, Int}}(),
    relational = Dict{Symbol, Tuple{Int, Int}}(),
    rules = Dict{Symbol, Bool}(),
)

# Apply a `[bands]` table into the override dicts: a relational name lands in
# `relational`, a scalar name in `bands`, anything else warns and is dropped, as a
# typo'd directive does.
function apply_bands!(acc, table, source)
    scalars = scalar_metric_names()
    for (name, value) in table
        sym = Symbol(name)
        if sym in RELATIONAL_BANDS
            acc.relational[sym] = band_tuple(value, name, source)
        elseif sym in scalars
            acc.bands[sym] = band_tuple(value, name, source)
        else
            @warn "Dendro: unknown band in $source, ignored" band = name
        end
    end
    return nothing
end

# Apply a `[rules]` table: each known rule name toggles on or off, anything else warns.
function apply_rules!(acc, table, source)
    known = rule_names()
    for (name, on) in table
        sym = Symbol(name)
        if sym in known
            acc.rules[sym] = Bool(on)
        else
            @warn "Dendro: unknown rule in $source, ignored" rule = name
        end
    end
    return nothing
end

# Apply a `[clones]` table: the three clone-detection thresholds (`min_size` named-node
# floor, near-miss `threshold`, candidate `radius_factor`), anything else warns.
function apply_clones(scalars, table, source)
    for (key, value) in table
        if key == "min_size"
            scalars = merge(scalars, (min_size = Int(value),))
        elseif key == "threshold"
            scalars = merge(scalars, (threshold = Float64(value),))
        elseif key == "radius_factor"
            scalars = merge(scalars, (radius_factor = Float64(value),))
        else
            @warn "Dendro: unknown clones key in $source, ignored" key
        end
    end
    return scalars
end

# Overlay one parsed TOML table onto the accumulating overrides, returning the scalar
# settings (`cut` and the clone thresholds) it leaves. Only the keys present are
# touched; an unknown top-level key warns rather than failing, so a file written for a
# newer Dendro still applies the keys this version knows.
function apply_toml!(acc, scalars, data, source)
    for (key, value) in data
        if key == "cut"
            scalars = merge(scalars, (cut = Float64(value),))
        elseif key == "clones"
            scalars = apply_clones(scalars, value, source)
        elseif key == "bands"
            apply_bands!(acc, value, source)
        elseif key == "rules"
            apply_rules!(acc, value, source)
        else
            @warn "Dendro: unknown key in $source, ignored" key
        end
    end
    return scalars
end

# The user-global config path, XDG-respecting, the layer above the built-in defaults.
function global_config_path()
    base = get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config"))
    return joinpath(base, "dendro", "config.toml")
end

# The directory a discovered `.dendro.toml` is looked for in: the git toplevel of the
# roots when they are in a repo, else the first root's own directory. Mirrors how the
# diff scope and the gate resolve a project root from the first path.
function repo_config_dir(roots)
    isempty(roots) && return nothing
    try
        return git_toplevel(roots)
    catch
        ref = first(roots)
        return isdir(ref) ? String(ref) : dirname(ref)
    end
end

# The config files to overlay, in cascade order: the user-global one, then either an
# explicit file (which must exist) or the discovered repo `.dendro.toml`. Missing
# discovered files are skipped; a missing explicit file is an error.
function config_files(roots, explicit)
    paths = String[]
    global_path = global_config_path()
    isfile(global_path) && push!(paths, global_path)
    if explicit !== nothing
        isfile(explicit) || error("Dendro: config file not found: $explicit")
        push!(paths, explicit)
    else
        dir = repo_config_dir(roots)
        repo_path = dir === nothing ? nothing : joinpath(dir, ".dendro.toml")
        repo_path !== nothing && isfile(repo_path) && push!(paths, repo_path)
    end
    return paths
end

"""
    discover_config(roots; explicit=nothing, use_files=true) -> Config

The resolved [`Config`](@ref) for analyzing `roots`: the built-in defaults overlaid
with the user-global config, then the repo `.dendro.toml`. `explicit` names a file to
read in place of the discovered repo one and must exist. `use_files = false` skips all
file layers, returning the built-in defaults.
"""
function discover_config(roots; explicit = nothing, use_files = true)
    acc = overrides()
    scalars = (cut = DEFAULT_CUT, min_size = DEFAULT_MIN_SIZE, threshold = DEFAULT_THRESHOLD, radius_factor = DEFAULT_RADIUS_FACTOR)
    if use_files
        for path in config_files(roots, explicit)
            scalars = apply_toml!(acc, scalars, TOML.parsefile(path), path)
        end
    end
    return Config(
        scalars.cut, acc.bands,
        get(acc.relational, :unnatural, UNNATURAL_BAND),
        get(acc.relational, :low_cohesion, LOW_COHESION_BAND),
        get(acc.relational, :scattered, SCATTERED_BAND),
        get(acc.relational, :misplaced, MISPLACED_BAND),
        acc.rules,
        scalars.min_size, scalars.threshold, scalars.radius_factor,
    )
end
