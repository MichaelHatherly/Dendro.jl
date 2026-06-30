# Tunable thresholds as data. Every band Dendro flags against is an opinion the
# bands philosophy calls retunable; this layer lets a project retune them from a
# `.dendro.toml` without editing source. The corpus floors and model internals stay
# fixed, out of the bargain: they are mechanism, not policy.
#
# Configuration is a cascade merged key by key, last wins:
#
#     built-in defaults  ->  ~/.config/dendro/config.toml  ->  repo .dendro.toml  ->  analyze kwargs
#
# The file populates a `Config`; `analyze` threads it through scoring. Discovery is
# source precedence, never spatial scoping: one corpus, one baseline, one set of
# bands per run, since the corpus-relative score is global and per-subtree bands
# would be incoherent with it.

# The four relational metrics carry their band as a `Config` field rather than the
# `bands` override dict, since they are not rules. A `[bands]` key naming one of these
# sets the field; any other `[bands]` key names a scalar rule.
const RELATIONAL_BANDS = (:unnatural, :low_cohesion, :scattered, :misplaced)

"""
    Config

Resolved tuning thresholds for one analysis. Built from the built-in defaults and
overlaid with the values a `.dendro.toml` sets. `cut` is the percentile cutoff;
`bands` overrides scalar rule `(warn, high)` tuples by metric name; the four
relational fields override the relational bands; `rules` toggles a rule on or off by
name. Pass one to [`analyze`](@ref) with `config =` to skip file discovery.
"""
mutable struct Config
    cut::Float64
    bands::Dict{Symbol, Tuple{Int, Int}}
    unnatural::Tuple{Int, Int}
    low_cohesion::Tuple{Int, Int}
    scattered::Tuple{Int, Int}
    misplaced::Tuple{Int, Int}
    rules::Dict{Symbol, Bool}
end

"""
    DEFAULT_CONFIG :: Config

The built-in defaults, the base layer of the cascade. Drawn from the same constants
the metrics read: the relational band consts and the `(warn, high)` tuples already in
[`BUILTIN_RULES`](@ref). `bands` and `rules` start empty; an absent override falls
back to a rule's own band and default on/off state.
"""
const DEFAULT_CONFIG = Config(
    0.95,
    Dict{Symbol, Tuple{Int, Int}}(),
    UNNATURAL_BAND,
    LOW_COHESION_BAND,
    SCATTERED_BAND,
    MISPLACED_BAND,
    Dict{Symbol, Bool}(),
)

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

# Apply a `[bands]` table: a relational name sets its field, a scalar name sets the
# override dict, anything else warns and is dropped, as a typo'd directive does.
function apply_bands!(config::Config, table, source)
    scalars = scalar_metric_names()
    for (name, value) in table
        sym = Symbol(name)
        if sym in RELATIONAL_BANDS
            setfield!(config, sym, band_tuple(value, name, source))
        elseif sym in scalars
            config.bands[sym] = band_tuple(value, name, source)
        else
            @warn "Dendro: unknown band in $source, ignored" band = name
        end
    end
    return config
end

# Apply a `[rules]` table: each known rule name toggles on or off, anything else warns.
function apply_rules!(config::Config, table, source)
    known = rule_names()
    for (name, on) in table
        sym = Symbol(name)
        if sym in known
            config.rules[sym] = Bool(on)
        else
            @warn "Dendro: unknown rule in $source, ignored" rule = name
        end
    end
    return config
end

# Overlay one parsed TOML table onto a config. Only the keys present are touched;
# an unknown top-level key warns rather than failing, so a forward-compatible file
# written for a newer Dendro still applies the keys this version knows.
function apply_toml!(config::Config, data, source)
    for (key, value) in data
        if key == "cut"
            config.cut = Float64(value)
        elseif key == "bands"
            apply_bands!(config, value, source)
        elseif key == "rules"
            apply_rules!(config, value, source)
        else
            @warn "Dendro: unknown key in $source, ignored" key
        end
    end
    return config
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

"""
    discover_config(roots; explicit=nothing, use_files=true) -> Config

The resolved [`Config`](@ref) for analyzing `roots`: the built-in defaults overlaid
with the user-global config, then the repo `.dendro.toml`. `explicit` names a file to
read in place of the discovered repo one and must exist. `use_files = false` skips
all file layers, returning the built-in defaults.
"""
function discover_config(roots; explicit = nothing, use_files = true)
    config = deepcopy(DEFAULT_CONFIG)
    use_files || return config
    global_path = global_config_path()
    isfile(global_path) && apply_toml!(config, TOML.parsefile(global_path), global_path)
    if explicit !== nothing
        isfile(explicit) || error("Dendro: config file not found: $explicit")
        apply_toml!(config, TOML.parsefile(explicit), explicit)
    else
        dir = repo_config_dir(roots)
        repo_path = dir === nothing ? nothing : joinpath(dir, ".dendro.toml")
        repo_path !== nothing && isfile(repo_path) &&
            apply_toml!(config, TOML.parsefile(repo_path), repo_path)
    end
    return config
end
