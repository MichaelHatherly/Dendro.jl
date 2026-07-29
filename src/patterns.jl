# User-authored lint rules as a second query family. `<lang>.scm` captures name the
# concepts every metric reads, a closed set. A `<lang>.patterns.scm` capture names a
# *rule*, an open set written against concrete grammar node types on purpose, since
# being language-specific is the point. The two never merge: merging takes `dispatch!`'s
# closure with it and metric code starts special-casing languages.
#
# A rule is declared once in `.dendro.toml`, language-independently, and realised per
# language by a query. The declaration carries what the finding says and how loud it is;
# the query carries the shape.

"""
    PatternSpec

One declared pattern rule. `name` is the metric a finding reports under and the name an
inline `dendro-ignore` accepts. `message` is what the rule says when it fires. `severity`
is `:warn` or `:high`, deciding whether the rule reaches the [`errors`](@ref) floor.
`kind` is `:flag` or `:scalar`; a scalar carries its `(warn, high)` `band` and a flag
carries `nothing`.
"""
struct PatternSpec
    name::Symbol
    message::String
    severity::Symbol
    kind::Symbol
    band::Union{Tuple{Int, Int}, Nothing}
end

# The severities a `[patterns.<name>]` table may name. `warn` is the default: `high_floor`
# treats a finding as gating when its absolute band is `:high`, so a rule that fires across
# a corpus would make `errors()` unsatisfiable. Promoting one is the project's call.
const PATTERN_SEVERITIES = (:warn, :high)

# The rule kinds. A flag reports presence, a scalar counts its matches per unit.
const PATTERN_KINDS = (:flag, :scalar)

# Coerce a TOML value naming one of a fixed set of symbols. Unlike an unknown key, which
# warns and is dropped, a bad value here is an error: the author clearly meant to set it,
# and guessing which of two severities they wanted would be worse than stopping.
function pattern_symbol(value, allowed, key, rule, source)::Symbol
    value isa AbstractString || config_error("`$key` for pattern `$rule` in $source must be a string, got $value")
    sym = Symbol(value)
    sym in allowed && return sym
    names = join(("`$a`" for a in allowed), ", ")
    return config_error("`$key` for pattern `$rule` in $source must be one of $names, got `$value`")
end

# Apply one `[patterns.<name>]` table. Only `message` is required; `severity` and `kind`
# default, and `band` is required by a scalar and rejected on a flag. An unknown key warns
# and is dropped, as a band does.
function apply_pattern!(acc, name::String, table::Dict{String, Any}, source)
    message = ""
    severity = :warn
    kind = :flag
    band = nothing
    for (key, value) in table
        if key == "message"
            message = config_string(value, "patterns.$name.$key", source)
        elseif key == "severity"
            severity = pattern_symbol(value, PATTERN_SEVERITIES, key, name, source)
        elseif key == "kind"
            kind = pattern_symbol(value, PATTERN_KINDS, key, name, source)
        elseif key == "band"
            band = band_tuple(value, "patterns.$name.$key", source)
        else
            @warn "Dendro: unknown pattern key in $source, ignored" pattern = name key
        end
    end
    isempty(message) && config_error("pattern `$name` in $source needs a `message`")
    validate_pattern_band(name, kind, band, source)
    acc.patterns[Symbol(name)] = PatternSpec(Symbol(name), message, severity, kind, band)
    return nothing
end

# A flag scores nothing, so a band on one is a declaration the author misunderstood. A
# scalar without a band has no absolute score at all. A scalar band starting below 1 lets
# `severity(0, band)` return something other than `:ok`, which would report every unit in
# the corpus for holding no matches.
function validate_pattern_band(name, kind::Symbol, band, source)
    if kind === :flag
        band === nothing || config_error("pattern `$name` in $source is a flag and cannot carry a `band`")
    else
        band === nothing && config_error("pattern `$name` in $source is a scalar and needs a `band`")
        first(band) >= 1 ||
            config_error("band for pattern `$name` in $source must start at 1 or higher, got $(first(band))")
    end
    return nothing
end

# `apply_patterns!`, the `[patterns]` table walk, lives in `config.jl` beside the
# `[languages]` one: the two differ only in the key prefix and the per-entry applier, so
# they share `apply_named_tables!`. What is pattern-specific is `apply_pattern!` above.
