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

# The relational metrics whose band a `[bands]` key may set. The rest of a `[bands]`
# table names scalar rules. Ordered as the `Config` fields and the constructor's keywords
# are, so the three lists read against each other.
const RELATIONAL_BANDS = (
    :unnatural, :low_cohesion, :file_length, :divisible_class, :scattered, :split_audience,
    :misplaced, :distant_definition, :back_edge, :dependency_cycle, :hub,
    :incoherent_package, :divisible_package, :child_count,
)

# A malformed `.dendro.toml` value: a band that is not two integers, a `cut` that is
# not a number, a rule toggle that is not a boolean. Carried as one exception type so
# the CLI reports it cleanly rather than as a stack trace, the same boundary stance the
# parse errors and usage errors already take.
struct ConfigError <: Exception
    msg::String
end

# The message is bare, like `CLIError`'s: the CLI prepends `dendro: `, an uncaught throw
# in a REPL reads `Dendro: ` through this `showerror`.
Base.showerror(io::IO, e::ConfigError) = print(io, "Dendro: ", e.msg)

config_error(msg) = throw(ConfigError(msg))

"""
    Config

Resolved tuning thresholds for one analysis, built by `discover_config` from the
built-in defaults and a `.dendro.toml`. `cut` is the percentile cutoff; `bands`
overrides scalar rule `(warn, high)` tuples by metric name; one field per relational
metric overrides that metric's band; `rules` toggles a rule on or off by name, and the
`reimplementation`, `incoherent_package`, `divisible_package` and `child_count` corpus passes
with it; `min_size`,
`threshold`, and `radius_factor`
are the clone-detection thresholds; `reimpl_threshold` is the reimplementation overlap
cutoff; `languages` carries the languages the config registers beyond the ones Dendro
ships, each a `LanguageProfile` naming where to load its grammar and queries from; and
`patterns` carries the user-authored lint rules the config declares, each a
[`PatternSpec`](@ref), sorted by name so a report reads in a stable order, and
`patterns_dir` overrides where their queries are read from (empty for the default,
`.dendro/patterns` beside the config); `library_threshold` and `library_gate_coverage`
are the cross-corpus duplication thresholds and `library_anchor_grain` widens the near pass
to compare blocks as well as whole functions; `libraries` holds the reference corpora a
`[libraries.<name>]` table declares, each a [`Library`](@ref), sorted by name; and
`ignore` holds gitignore-style patterns dropping paths from the scan, which
[`analyze`](@ref)'s own `ignore` keyword adds to rather than replaces; `generated` holds
signatures matched against a file's head beside the built-in ones, and `generated_enabled`
is whether that filter runs at all; `base_summary`
controls whether a scan with a base ref scores that revision for comparison.
Every field is a keyword taking that field's type and defaulting to its built-in, so
`Config(; misplaced = (40, 60))` retunes one band and keeps the rest. Immutable: pass one
to [`analyze`](@ref) with `config =` to skip file discovery.
"""
struct Config
    cut::Float64
    bands::Dict{Symbol, Tuple{Int, Int}}
    unnatural::Tuple{Int, Int}
    low_cohesion::Tuple{Int, Int}
    file_length::Tuple{Int, Int}
    divisible_class::Tuple{Int, Int}
    scattered::Tuple{Int, Int}
    split_audience::Tuple{Int, Int}
    misplaced::Tuple{Int, Int}
    distant_definition::Tuple{Int, Int}
    back_edge::Tuple{Int, Int}
    dependency_cycle::Tuple{Int, Int}
    hub::Tuple{Int, Int}
    incoherent_package::Tuple{Int, Int}
    divisible_package::Tuple{Int, Int}
    child_count::Tuple{Int, Int}
    rules::Dict{Symbol, Bool}
    min_size::Int
    threshold::Float64
    radius_factor::Float64
    reimpl_threshold::Float64
    library_threshold::Float64
    library_gate_coverage::Int
    library_anchor_grain::Bool
    languages::Dict{Symbol, LanguageProfile}
    patterns::Vector{PatternSpec}
    patterns_dir::String
    libraries::Vector{Library}
    ignore::Vector{String}
    generated::Vector{String}
    generated_enabled::Bool
    base_summary::Bool

    # Built by keyword, never positionally. Twelve fields in a row are `Tuple{Int, Int}`
    # bands, so a positional call admits an argument list that compiles, typechecks, and
    # attaches each band to the wrong metric; two branches each adding a metric merge into
    # one. Each default is the built-in the cascade starts from, so a caller names only
    # what it sets, and each keyword takes its field's own type rather than converting to
    # it: every value arriving here has been coerced by a `config_*` helper already.
    Config(;
        cut::Float64 = DEFAULT_CUT,
        bands::Dict{Symbol, Tuple{Int, Int}} = Dict{Symbol, Tuple{Int, Int}}(),
        unnatural::Tuple{Int, Int} = UNNATURAL_BAND,
        low_cohesion::Tuple{Int, Int} = LOW_COHESION_BAND,
        file_length::Tuple{Int, Int} = FILE_LENGTH_BAND,
        divisible_class::Tuple{Int, Int} = DIVISIBLE_CLASS_BAND,
        scattered::Tuple{Int, Int} = SCATTERED_BAND,
        split_audience::Tuple{Int, Int} = SPLIT_AUDIENCE_BAND,
        misplaced::Tuple{Int, Int} = MISPLACED_BAND,
        distant_definition::Tuple{Int, Int} = DISTANT_DEFINITION_BAND,
        back_edge::Tuple{Int, Int} = BACK_EDGE_BAND,
        dependency_cycle::Tuple{Int, Int} = DEPENDENCY_CYCLE_BAND,
        hub::Tuple{Int, Int} = HUB_BAND,
        incoherent_package::Tuple{Int, Int} = INCOHERENT_PACKAGE_BAND,
        divisible_package::Tuple{Int, Int} = DIVISIBLE_PACKAGE_BAND,
        child_count::Tuple{Int, Int} = CHILD_COUNT_BAND,
        rules::Dict{Symbol, Bool} = Dict{Symbol, Bool}(),
        min_size::Int = DEFAULT_MIN_SIZE,
        threshold::Float64 = DEFAULT_THRESHOLD,
        radius_factor::Float64 = DEFAULT_RADIUS_FACTOR,
        reimpl_threshold::Float64 = DEFAULT_REIMPL_THRESHOLD,
        library_threshold::Float64 = DEFAULT_LIBRARY_THRESHOLD,
        library_gate_coverage::Int = DEFAULT_LIBRARY_GATE_COVERAGE,
        library_anchor_grain::Bool = false,
        languages::Dict{Symbol, LanguageProfile} = Dict{Symbol, LanguageProfile}(),
        patterns::Vector{PatternSpec} = PatternSpec[],
        patterns_dir::String = "",
        libraries::Vector{Library} = Library[],
        ignore::Vector{String} = String[],
        generated::Vector{String} = String[],
        generated_enabled::Bool = true,
        base_summary::Bool = true,
    ) = new(
        cut, bands, unnatural, low_cohesion, file_length, divisible_class, scattered,
        split_audience, misplaced, distant_definition, back_edge, dependency_cycle, hub,
        incoherent_package, divisible_package, child_count, rules, min_size, threshold, radius_factor,
        reimpl_threshold, library_threshold, library_gate_coverage, library_anchor_grain,
        languages, patterns, patterns_dir, libraries, ignore, generated, generated_enabled,
        base_summary,
    )
end

"""
    resolve_profiles(config) -> Dict{Symbol, LanguageProfile}

The language registry the config selects: [`PROFILES`](@ref), the languages Dendro
ships, overlaid with the ones `config` registers. A configured language of the same name
as a built-in replaces it. The built-in table is never mutated, so one analysis cannot
leak a registration into the next.
"""
resolve_profiles(config::Config) = merge(PROFILES, config.languages)

# The scalar metric names a `[bands]` key may set: every scalar rule, built-in or
# optional, plus the scalar pattern rules the same config declares. Flag rules carry no
# band, so naming one under `[bands]` is an error. Pattern names come from the
# accumulator rather than a constant, since a project's own rules are only known once its
# config has been read.
scalar_metric_names(acc) = union(
    Set(r.name for r in [BUILTIN_RULES; OPTIONAL_RULES] if r.kind === :scalar),
    Set(s.name for s in values(acc.patterns) if s.kind === :scalar),
)

# Corpus passes a `[rules]` key may toggle alongside the per-unit rules. They are
# gated in `analyze` rather than resolved into the rule set, so `resolve_rules`
# ignores these names.
const TOGGLEABLE_RELATIONAL = (
    :reimplementation, :incoherent_package, :divisible_package, :child_count,
    :distant_definition, :divisible_class,
    :library_duplicate, :library_near_duplicate,
)

# Every rule name a `[rules]` key may toggle: built-in or optional, of either kind, the
# toggleable corpus passes, and the pattern rules the same config declares, so a project
# turns its own rule off the way it turns `cyclomatic` off.
rule_names(acc) = union(
    Set(r.name for r in [BUILTIN_RULES; OPTIONAL_RULES]),
    TOGGLEABLE_RELATIONAL, keys(acc.patterns),
)

"""
    resolve_rules(config) -> Vector{Rule}

The active rule set the config selects: [`BUILTIN_RULES`](@ref) minus the names
`config` disables, plus the [`OPTIONAL_RULES`](@ref) it enables, then one rule per
user-authored `[patterns.<name>]` declaration, each scalar rule's band replaced by a
`config` override when one is set. A pattern rule toggles off through `[rules]` by the
same name a built-in does. The default carries the same rules `analyze` used before
configuration.
"""
function resolve_rules(config::Config)
    out = Rule[]
    for (rules, default_on) in ((BUILTIN_RULES, true), (OPTIONAL_RULES, false))
        for r in rules
            get(config.rules, r.name, default_on) && push!(out, reband(r, config))
        end
    end
    for spec in config.patterns
        get(config.rules, spec.name, true) && push!(out, reband(pattern_rule(spec), config))
    end
    return out
end

# A rule with its band replaced by the config override, when the metric carries one.
reband(r::Rule, config::Config) =
    haskey(config.bands, r.name) ?
    Rule(r.name, r.kind, config.bands[r.name], r.fn, r.severity, r.scope) : r

# Coerce a TOML value to the type a config field reads, erroring on a malformed one so a
# typo fails loud rather than scoring against garbage. The `isa` guard narrows the `Any` a
# TOML dict yields to a concrete type, so the values reaching `Config` are typed. Inlined:
# the residual conversion folds into the caller, attributed to Base, rather than reading as
# a Dendro-side dynamic dispatch the way a wrapper call would.
#
# `config_float` and `config_int` are the same guard-and-convert shape with the guard type,
# converter, and noun swapped, so the clone detector pairs them; folding them into one
# type-parameterised helper only moves the duplication to four identical call sites, larger
# and worse. Kept parallel, the float one suppressed.
@inline config_float(value, key, source)::Float64 =
    value isa Real ? Float64(value) : config_error("`$key` in $source must be a number, got $value")

# dendro-ignore: duplicate
@inline config_int(value, key, source)::Int =
    value isa Integer ? Int(value) : config_error("`$key` in $source must be an integer, got $value")

@inline config_bool(value, key, source)::Bool =
    value isa Bool ? value : config_error("`$key` in $source must be true or false, got $value")

@inline config_table(value, key, source)::Dict{String, Any} =
    value isa AbstractDict ? Dict{String, Any}(value) : config_error("`$key` in $source must be a table")

@inline config_string(value, key, source)::String =
    value isa AbstractString ? String(value) : config_error("`$key` in $source must be a string, got $value")

# A path read from a config file, resolved against that file's own directory rather than
# the process working directory. A config is discovered from a repo root while `dendro`
# may be run from any subdirectory, so a relative path stored verbatim resolves against
# whichever directory the caller happened to be in.
config_path(value, key, source)::String =
    (p = config_string(value, key, source); isabspath(p) ? p : normpath(joinpath(dirname(String(source)), p)))

# Coerce a TOML `[warn, high]` array into the band tuple `severity` reads.
@inline function band_tuple(value, name, source)::Tuple{Int, Int}
    if value isa AbstractVector && length(value) == 2
        lo, hi = value[1], value[2]
        lo isa Integer && hi isa Integer && return (Int(lo), Int(hi))
    end
    config_error("band `$name` in $source must be two integers [warn, high], got $value")
end

# The override dicts an analysis accumulates across config layers: scalar bands,
# relational bands, and rule toggles. Bundled so `apply_toml!` carries one accumulator
# rather than three, keeping its own metrics out of the warn band.
overrides() = (
    bands = Dict{Symbol, Tuple{Int, Int}}(),
    relational = Dict{Symbol, Tuple{Int, Int}}(),
    rules = Dict{Symbol, Bool}(),
    languages = Dict{Symbol, LanguageProfile}(),
    patterns = Dict{Symbol, PatternSpec}(),
    libraries = Dict{String, Library}(),
)

# Apply a `[bands]` table into the override dicts: a relational name lands in
# `relational`, a scalar name in `bands`, anything else warns and is dropped, as a
# typo'd directive does.
function apply_bands!(acc, table, source)
    scalars = scalar_metric_names(acc)
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
    known = rule_names(acc)
    for (name, on) in table
        sym = Symbol(name)
        if sym in known
            acc.rules[sym] = config_bool(on, name, source)
        else
            @warn "Dendro: unknown rule in $source, ignored" rule = name
        end
    end
    return nothing
end

# Apply a `[clones]` table: the three clone-detection thresholds (`min_size` named-node
# floor, near-miss `threshold`, candidate `radius_factor`) and the two cross-corpus ones
# (`library_threshold`, `library_gate_coverage`), anything else warns. The library keys
# live here rather than in a table of their own: they are clone-detection thresholds, and
# a `[library]` table a letter away from `[libraries]` is the typo that would silently
# discard a setting, since an unknown top-level key warns and is dropped.
function apply_clones(scalars, table, source)
    for (key, value) in table
        if key == "min_size"
            scalars = merge(scalars, (min_size = config_int(value, key, source),))
        elseif key == "threshold"
            scalars = merge(scalars, (threshold = config_float(value, key, source),))
        elseif key == "radius_factor"
            scalars = merge(scalars, (radius_factor = config_float(value, key, source),))
        elseif key == "library_threshold"
            scalars = merge(scalars, (library_threshold = config_float(value, key, source),))
        elseif key == "library_gate_coverage"
            scalars = merge(scalars, (library_gate_coverage = config_int(value, key, source),))
        elseif key == "library_anchor_grain"
            scalars = merge(scalars, (library_anchor_grain = config_bool(value, key, source),))
        else
            @warn "Dendro: unknown clones key in $source, ignored" key
        end
    end
    return scalars
end

# Apply a table holding one scalar setting: `setting` lands in `field` of the scalar
# overrides through `coerce`, any other key in the `name` table warns.
function apply_scalar_key(
        scalars::S, table::Dict{String, Any}, source,
        name::String, setting::String, field::Symbol, coerce::F
    ) where {S, F}
    for (key, value) in table
        if key == setting
            # `field` and `coerce` come from a table, so the merge is abstract where every
            # other applier's is concrete. The assertion holds because a scalar table only
            # ever sets a default the overrides already carry, at that default's type.
            scalars = merge(scalars, NamedTuple{(field,)}((coerce(value, key, source),)))::S
        else
            @warn "Dendro: unknown $name key in $source, ignored" key
        end
    end
    return scalars
end

# Coerce a TOML array of strings, the shape a library's `paths` and `ignore` take and the
# raw form an extension list is read from.
function string_list(value, key, source)::Vector{String}
    value isa AbstractVector ||
        config_error("`$key` in $source must be an array of strings, got $value")
    out = String[]
    for s in value
        s isa AbstractString ||
            config_error("`$key` in $source must be an array of strings, got $value")
        push!(out, String(s))
    end
    return out
end

# Coerce a TOML array of extensions, stripping any leading dot so `[".zig"]` and
# `["zig"]` both reach the registry in the form `language_for_path` compares.
extension_list(value, key, source)::Vector{String} =
    String[lowercase(lstrip(e, '.')) for e in string_list(value, key, source)]

# Apply one `[languages.<name>]` table into the override dict. Only `queries` is required:
# `grammar` defaults to the language name, which resolves to the JLL named after it, so
# retuning a built-in language's query is a two-line table. Extensions are optional too,
# since a language registered over a built-in keeps the extensions that one claims. An
# unknown key warns and is dropped, as a band does.
function apply_language!(acc, name::String, table::Dict{String, Any}, source)
    sym = Symbol(name)
    grammar = name
    queries = ""
    extensions = String[]
    for (key, value) in table
        if key == "grammar"
            grammar = config_string(value, "languages.$name.$key", source)
        elseif key == "queries"
            # Resolved against the config that declared it, as `patterns_dir` is: a
            # relative path stored verbatim resolves against whichever directory `dendro`
            # happened to be run from.
            queries = config_path(value, "languages.$name.$key", source)
        elseif key == "extensions"
            extensions = extension_list(value, "languages.$name.$key", source)
        else
            @warn "Dendro: unknown language key in $source, ignored" language = name key
        end
    end
    isempty(queries) && config_error("language `$name` in $source needs a `queries` directory")
    acc.languages[sym] = LanguageProfile(sym, grammar, queries, extensions)
    return nothing
end

# One path component expanded against a directory: the entries whose name the component
# matches, sorted so a scan reads the same way on every run. A component with no `*` is
# taken literally, so a path that never globs costs no directory listing.
function glob_entries(dir::String, part::String)
    occursin('*', part) || return [joinpath(dir, part)]
    isdir(dir) || return String[]
    re = glob_to_regex(part)
    return String[joinpath(dir, e) for e in sort!(readdir(dir)) if occursin(re, e)]
end

# The directories a configured library path names. A single `*` per component expands as a
# filesystem glob, which is what makes `~/.julia/packages/IterTools/*/src` survive a
# version bump. `**` is refused: one `*` covers the version-slug case, and recursive
# globbing over a package depot is a way to index gigabytes by accident.
#
# A path matching nothing is an error rather than a warning, the asymmetry with an unknown
# key inside the same table: a typo'd key leaves the rest of the table working, where a
# path resolving to nothing silently turns the gate off, which is the failure this whole
# feature exists to prevent.
function library_dirs(raw::AbstractString, key, source)
    occursin("**", raw) &&
        config_error("`$key` in $source may use one `*` per path component, not `**`")
    path = config_path(expanduser(String(raw)), key, source)
    parts = splitpath(path)
    dirs = String[first(parts)]
    for part in Iterators.drop(parts, 1)
        next = String[]
        for d in dirs
            append!(next, glob_entries(d, part))
        end
        dirs = next
    end
    filter!(isdir, dirs)
    isempty(dirs) && config_error("`$key` in $source matched no directory: $path")
    return dirs
end

# One `[libraries.<name>]` table read into the override dict: `path` or `paths`, at least
# one required, with `ignore` optional. Paths expand `~`, resolve against the config file's
# own directory, and glob. An unknown key warns and is dropped, as a band does.
function apply_library!(acc, name::String, table::Dict{String, Any}, source)
    roots = String[]
    ignore = String[]
    for (key, value) in table
        full = "libraries.$name.$key"
        if key == "path"
            append!(roots, library_dirs(config_string(value, full, source), full, source))
        elseif key == "paths"
            for p in string_list(value, full, source)
                append!(roots, library_dirs(p, full, source))
            end
        elseif key == "ignore"
            append!(ignore, string_list(value, full, source))
        else
            @warn "Dendro: unknown library key in $source, ignored" library = name key
        end
    end
    isempty(roots) && config_error("library `$name` in $source needs a `path` or `paths`")
    acc.libraries[name] = Library(name, roots; ignore)
    return nothing
end

# Apply a table of named subtables: `[<prefix>.<name>]` becomes one `applier` call per
# entry, carrying the entry's name and its narrowed table. The key type is spelled out so
# the applier reads a concrete table rather than an `Any` TOML value, the same narrowing
# the `config_*` coercion helpers do. `[languages]` and `[patterns]` are both this shape,
# differing only in the prefix and what each entry means.
function apply_named_tables!(applier::F, acc, table::Dict{String, Any}, prefix, source) where {F}
    for (name, value) in table
        applier(acc, name, config_table(value, "$prefix.$name", source), source)
    end
    return nothing
end

# `[languages]` and `[patterns]` reach this directly from `apply_toml!` rather than
# through a named wrapper each: the wrappers would differ only in two arguments, which is
# a forwarding pair rather than two ideas.

# Overlay one parsed TOML table onto the accumulating overrides, returning the scalar
# settings (`cut` and the clone thresholds) it leaves. Only the keys present are
# touched; an unknown top-level key warns rather than failing, so a file written for a
# newer Dendro still applies the keys this version knows.
# The order keys are applied in, which matters where one table's validation reads another's
# result: `[bands]` checks a band name against the scalar rules, and a project's own
# `[patterns]` declarations are among them, so patterns must land first. TOML parses to a
# Dict, whose iteration order is arbitrary, so relying on file order would make a config
# apply differently run to run.
const CONFIG_KEY_ORDER = (
    "patterns", "languages", "libraries", "cut", "clones", "reimplementation", "report",
    "patterns_dir", "ignore", "generated", "bands", "rules",
)

function apply_toml!(acc, scalars, data::Dict{String, Any}, source)
    for key in CONFIG_KEY_ORDER
        haskey(data, key) || continue
        scalars = apply_key!(acc, scalars, key, data[key], source)
    end
    for key in keys(data)
        key in CONFIG_KEY_ORDER || @warn "Dendro: unknown key in $source, ignored" key
    end
    return scalars
end

# Tables holding one scalar setting each: the key inside the table, the field of the
# scalar overrides it lands in, and the coercion that reads it. `[reimplementation]` sets
# the overlap `threshold` a candidate pair must reach; `[report]` sets whether a
# base-scoped scan scores the base corpus for the comparison columns.
const SCALAR_TABLES = Dict{String, Tuple{String, Symbol, Function}}(
    "reimplementation" => ("threshold", :reimpl_threshold, config_float),
    "report" => ("base_summary", :base_summary, config_bool),
)

# The top-level `generated` key: an array of signatures to match beside the built-in ones,
# or a boolean turning the content filter off and on. `false` is there for the project whose
# own source names a bundler in a file header, since the key adds to the built-in list and
# takes nothing out of it. A later config layer replaces an earlier one, the way `ignore` does.
function apply_generated(scalars, value, key, source)
    value isa Bool && return merge(scalars, (generated = String[], generated_enabled = value))
    return merge(scalars, (generated = string_list(value, key, source), generated_enabled = true))
end

# Apply one known top-level key, returning the scalar settings it leaves.
function apply_key!(acc, scalars, key, value, source)
    if key == "cut"
        scalars = merge(scalars, (cut = config_float(value, key, source),))
    elseif key == "clones"
        scalars = apply_clones(scalars, config_table(value, key, source), source)
    elseif haskey(SCALAR_TABLES, key)
        setting, field, coerce = SCALAR_TABLES[key]
        table = config_table(value, key, source)
        scalars = apply_scalar_key(scalars, table, source, key, setting, field, coerce)
    elseif key == "bands"
        apply_bands!(acc, config_table(value, key, source), source)
    elseif key == "rules"
        apply_rules!(acc, config_table(value, key, source), source)
    elseif key == "patterns_dir"
        scalars = merge(scalars, (patterns_dir = config_path(value, key, source),))
    elseif key == "ignore"
        scalars = merge(scalars, (ignore = string_list(value, key, source),))
    elseif key == "generated"
        scalars = apply_generated(scalars, value, key, source)
    else
        applier = key == "languages" ? apply_language! :
            key == "libraries" ? apply_library! : apply_pattern!
        apply_named_tables!(applier, acc, config_table(value, key, source), key, source)
    end
    return scalars
end

"""
    xdg_path(var, default, parts...) -> String

A Dendro path under an XDG base directory: `\$<var>/dendro/<parts...>`, falling back to the
specification's default under the home directory when the variable is unset. The config
cascade's user-global layer is this, a file a user edits and expects to find where the
specification says. Cached data is not: the reference-index cache is a scratch space the
package owns, which `Pkg.gc()` knows how to reclaim.
"""
xdg_path(var::String, default::String, parts::String...) =
    joinpath(get(ENV, var, joinpath(homedir(), default)), "dendro", parts...)

# The user-global config path, the layer above the built-in defaults.
global_config_path() = xdg_path("XDG_CONFIG_HOME", ".config", "config.toml")

# The directory a discovered `.dendro.toml` is looked for in: the git toplevel of the
# roots when they are in a repo, else the first root's own directory. Mirrors how the
# diff scope and the gate resolve a project root from the first path.
function repo_config_dir(roots)
    isempty(roots) && return nothing
    try
        return git_toplevel(roots)
        # dendro-ignore: empty_catch_binding -- the only question is whether git answered
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
        isfile(explicit) || config_error("config file not found: $explicit")
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
read in place of the discovered repo one and must exist. `use_files = false` skips the
discovered layers, returning the built-in defaults.

The pack of rules Dendro ships is among those defaults. It is applied as the layer below
the user-global config, through the same walk a config file takes, so a project disables
one of its rules, retunes a band, or replaces a declaration with the keys it already has
for its own rules.
"""
function discover_config(roots; explicit = nothing, use_files = true)
    acc = overrides()
    scalars = (
        cut = DEFAULT_CUT, min_size = DEFAULT_MIN_SIZE, threshold = DEFAULT_THRESHOLD,
        radius_factor = DEFAULT_RADIUS_FACTOR, reimpl_threshold = DEFAULT_REIMPL_THRESHOLD,
        library_threshold = DEFAULT_LIBRARY_THRESHOLD,
        library_gate_coverage = DEFAULT_LIBRARY_GATE_COVERAGE,
        library_anchor_grain = false,
        patterns_dir = "",
        ignore = String[],
        generated = String[],
        generated_enabled = true,
        base_summary = true,
    )
    builtin = builtin_patterns_file()
    scalars = apply_toml!(acc, scalars, TOML.parsefile(builtin), builtin)
    if use_files
        for path in config_files(roots, explicit)
            scalars = apply_toml!(acc, scalars, TOML.parsefile(path), path)
        end
    end
    return Config(;
        cut = scalars.cut,
        bands = acc.bands,
        unnatural = get(acc.relational, :unnatural, UNNATURAL_BAND),
        low_cohesion = get(acc.relational, :low_cohesion, LOW_COHESION_BAND),
        file_length = get(acc.relational, :file_length, FILE_LENGTH_BAND),
        divisible_class = get(acc.relational, :divisible_class, DIVISIBLE_CLASS_BAND),
        scattered = get(acc.relational, :scattered, SCATTERED_BAND),
        split_audience = get(acc.relational, :split_audience, SPLIT_AUDIENCE_BAND),
        misplaced = get(acc.relational, :misplaced, MISPLACED_BAND),
        distant_definition = get(acc.relational, :distant_definition, DISTANT_DEFINITION_BAND),
        back_edge = get(acc.relational, :back_edge, BACK_EDGE_BAND),
        dependency_cycle = get(acc.relational, :dependency_cycle, DEPENDENCY_CYCLE_BAND),
        hub = get(acc.relational, :hub, HUB_BAND),
        incoherent_package = get(acc.relational, :incoherent_package, INCOHERENT_PACKAGE_BAND),
        divisible_package = get(acc.relational, :divisible_package, DIVISIBLE_PACKAGE_BAND),
        child_count = get(acc.relational, :child_count, CHILD_COUNT_BAND),
        rules = acc.rules,
        min_size = scalars.min_size,
        threshold = scalars.threshold,
        radius_factor = scalars.radius_factor,
        reimpl_threshold = scalars.reimpl_threshold,
        library_threshold = scalars.library_threshold,
        library_gate_coverage = scalars.library_gate_coverage,
        library_anchor_grain = scalars.library_anchor_grain,
        languages = acc.languages,
        patterns = sort!(collect(values(acc.patterns)); by = s -> s.name),
        patterns_dir = scalars.patterns_dir,
        libraries = sort!(collect(values(acc.libraries)); by = l -> l.name),
        ignore = scalars.ignore,
        generated = scalars.generated,
        generated_enabled = scalars.generated_enabled,
        base_summary = scalars.base_summary,
    )
end

"""
    override_config(config; cut=nothing, min_size=nothing, threshold=nothing, radius_factor=nothing, libraries=nothing) -> Config

`config` with the thresholds a caller named directly applied over it, the last layer of
the cascade [`discover_config`](@ref) resolves the earlier ones of. A `nothing` keeps the
config's own value.

[`analyze`](@ref) folds its keywords in through this, so a threshold is resolved once and
every pass reads it from the same place rather than from a keyword the caller may or may
not have set. `libraries` accepts [`Library`](@ref) values or bare root paths, a string
being one root.
"""
function override_config(
        config::Config; cut = nothing, min_size = nothing,
        threshold = nothing, radius_factor = nothing, libraries = nothing
    )
    return Config(;
        cut = cut === nothing ? config.cut : Float64(cut),
        bands = config.bands,
        unnatural = config.unnatural,
        low_cohesion = config.low_cohesion,
        file_length = config.file_length,
        divisible_class = config.divisible_class,
        scattered = config.scattered,
        split_audience = config.split_audience,
        misplaced = config.misplaced,
        distant_definition = config.distant_definition,
        back_edge = config.back_edge,
        dependency_cycle = config.dependency_cycle,
        hub = config.hub,
        incoherent_package = config.incoherent_package,
        divisible_package = config.divisible_package,
        child_count = config.child_count,
        rules = config.rules,
        min_size = min_size === nothing ? config.min_size : Int(min_size),
        threshold = threshold === nothing ? config.threshold : Float64(threshold),
        radius_factor = radius_factor === nothing ? config.radius_factor : Float64(radius_factor),
        reimpl_threshold = config.reimpl_threshold,
        library_threshold = config.library_threshold,
        library_gate_coverage = config.library_gate_coverage,
        library_anchor_grain = config.library_anchor_grain,
        languages = config.languages,
        patterns = config.patterns,
        patterns_dir = config.patterns_dir,
        libraries = libraries === nothing ? config.libraries : as_libraries(libraries),
        ignore = config.ignore,
        generated = config.generated,
        generated_enabled = config.generated_enabled,
        base_summary = config.base_summary,
    )
end
