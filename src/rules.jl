# Lint rules as data. A rule pairs a metric name with the function that measures
# it, so the active rule set is a value `analyze` carries rather than a fixed set
# of constants. The built-ins below are the default; a caller appends their own.

"""
    Rule

One lint rule. `name` is the metric a finding reports under and the name an
inline `dendro-ignore` directive accepts. `kind` is `:scalar` or `:flag`. A
scalar rule carries its `(warn, high)` `band`; a flag rule carries `nothing`.
`fn` measures one unit or the whole index:

- scalar `fn(unit, index) -> Int`, scored against the band and the corpus
  percentile.
- flag `fn(index) -> Vector{TreeSitter.Node}`, one finding per returned node.

`scope` says which units a scalar rule measures: `:any`, or `:callable` for a rule
that asks about a definition. `function_length` measures the distance to a boundary
an author drew and `parameter_count` reads a signature, and top-level code has
neither, so a band calibrated on definitions must not be read there.

`severity` is the absolute band a flag rule's findings carry, and is meaningful
only for a flag: a scalar reads its band instead. Every built-in flag is `:high`,
which is what puts it in the [`errors`](@ref) floor. A user-authored pattern rule
defaults to `:warn`, since a rule firing across a corpus would otherwise make the
gate unsatisfiable. The two kind-specific fields mirror each other: `band` is
scalar-only, `severity` flag-only.

`fn` is abstractly typed, so calling it dispatches dynamically. Parametrising it
would make every rule a distinct type, and the rule set is a `Vector{Rule}` a
project extends at run time, which needs one. The dispatch is paid once per unit
per rule, never per node.
"""
struct Rule
    name::Symbol
    kind::Symbol
    band::Union{Tuple{Int, Int}, Nothing}
    fn::Function    # dendro-ignore: abstract_field
    severity::Symbol
    scope::Symbol
end

# The built-in rules predate the severity field and every one of them is `:high`, so it
# defaults rather than being repeated fifteen times. Most rules measure any unit, so
# `scope` defaults the same way.
Rule(name::Symbol, kind::Symbol, band, fn) = Rule(name, kind, band, fn, :high, :any)
Rule(name::Symbol, kind::Symbol, band, fn, severity::Symbol) =
    Rule(name, kind, band, fn, severity, :any)


"""
    applies(rule, unit, index) -> Bool

Whether `rule` measures `unit`. A `:callable` rule asks about a definition, its
signature or the distance to a boundary an author drew, and top-level code has
neither, so the rule says nothing there instead of reading a number against a band
calibrated on definitions.
"""
applies(rule::Rule, unit::Unit, index::QueryIndex) =
    rule.scope === :any || is_callable(unit, index)

"""
    PatternSpec

One user-authored lint rule, as declared by a `[patterns.<name>]` table in a
`.dendro.toml`. Where a [`Rule`](@ref) carries the function that measures, a spec carries
what a project said it wants; `pattern_rule` turns one into the other once the query
behind it has compiled.

`name` is the metric a finding reports under and the name an inline `dendro-ignore`
accepts. `message` is what the rule says when it fires. `severity` is `:warn` or `:high`,
deciding whether the rule reaches the [`errors`](@ref) floor. `kind` is `:flag` or
`:scalar`; a scalar carries its `(warn, high)` `band` and a flag carries `nothing`.

`scope` is the unit kind a scalar rule measures, `:any` or `:callable`, the same
declaration a built-in [`Rule`](@ref) carries. A rule counting a shape "in one function"
means the definitions, and top-level code is not one.

`guard` says the rule is written to catch something the project intends never to write, so
matching nothing is the state it wants rather than a rule to go and fix. Only the zero-match
report reads it, and everything else treats a guard as any other rule. Without it that
report, which exists to catch a query naming a shape the grammar never produces, cannot tell
that case from a rule doing its job.

The declaration is language-independent. One `<lang>.patterns.scm` per grammar realises
it, so a rule says one thing across every language a project scans.
"""
struct PatternSpec
    name::Symbol
    message::String
    severity::Symbol
    kind::Symbol
    band::Union{Tuple{Int, Int}, Nothing}
    guard::Bool
    scope::Symbol
end
PatternSpec(name::Symbol, message::String, severity::Symbol, kind::Symbol, band, guard::Bool = false) =
    PatternSpec(name, message, severity, kind, band, guard, :any)

# The severities a `[patterns.<name>]` table may name. `warn` is the default: `high_floor`
# gates on an absolute band of `:high`, so a rule that fires across a corpus would make
# `errors()` unsatisfiable. Promoting one is the project's call.
const PATTERN_SEVERITIES = (:warn, :high)

# The rule kinds. A flag reports presence, a scalar counts its matches per unit.
const PATTERN_KINDS = (:flag, :scalar)

# The unit kinds a rule may measure. `:any` is the default: a lint rule is about a shape,
# and a shape is a shape wherever it sits. A rule whose count only means something inside a
# definition declares `:callable`.
const PATTERN_SCOPES = (:any, :callable)

"""
    BUILTIN_RULES :: Vector{Rule}

The default rule set, in report order. Scalar bands are fixed `(warn, high)`
targets, so a uniformly-weak codebase has a standard to improve toward rather than
only its own median. Drawn from common complexity guidance. Pass `rules` to
[`analyze`](@ref) to extend or replace them.
"""
const BUILTIN_RULES = Rule[
    Rule(:cyclomatic, :scalar, (11, 21), cyclomatic),
    Rule(:cognitive_complexity, :scalar, (15, 25), cognitive_complexity),
    Rule(:function_length, :scalar, (50, 100), (u, i) -> function_length(u), :high, :callable),
    Rule(:nesting_depth, :scalar, (4, 6), nesting_depth),
    Rule(:parameter_count, :scalar, (5, 8), parameter_count, :high, :callable),
    Rule(:boolean_complexity, :scalar, (4, 6), boolean_complexity),
    Rule(:identical_operands, :flag, nothing, identical_operands),
    Rule(:duplicate_branches, :flag, nothing, duplicate_branches),
    Rule(:empty_body, :flag, nothing, empty_bodies),
    Rule(:empty_catch, :flag, nothing, empty_catches),
    Rule(:stub_marker, :flag, nothing, stub_markers),
    Rule(:return_in_finally, :flag, nothing, returns_in_finally),
    Rule(:unused_parameter, :flag, nothing, unused_parameters),
    Rule(:unused_local, :flag, nothing, unused_locals),
    Rule(:broad_catch, :flag, nothing, broad_catches),
]

"""
    OPTIONAL_RULES :: Vector{Rule}

Rules a caller can opt into but that are off by default: `return_count` needs
per-project band tuning, `trivial_wrapper` has a higher false-positive rate,
`unreachable_after_jump` flags code after an unconditional jump, `npath` grows
multiplicatively so its band wants per-project tuning, `local_count` likewise,
`shadowed_variable` reads name collisions some idioms make routine (a method
local matching a class attribute), and `fan_out` cannot separate a smell from a
legitimate orchestrator by any fixed band (idiomatic corpora run p99 from 9 to
26 distinct callees). Use them with
`analyze(path; rules = [BUILTIN_RULES; OPTIONAL_RULES])`.
"""
const OPTIONAL_RULES = Rule[
    Rule(:return_count, :scalar, (4, 8), return_count, :high, :callable),
    Rule(:trivial_wrapper, :flag, nothing, trivial_wrappers),
    Rule(:unreachable_after_jump, :flag, nothing, unreachable_statements),
    Rule(:npath, :scalar, (200, 1000), npath),
    Rule(:local_count, :scalar, (10, 15), local_count, :high, :callable),
    Rule(:shadowed_variable, :flag, nothing, shadowed_variables),
    Rule(:fan_out, :scalar, (12, 20), fan_out),
]

# The active rules of one kind (`:scalar` or `:flag`), in order.
rules_of_kind(rules, kind::Symbol) = Iterators.filter(r -> r.kind == kind, rules)

# Metrics produced by corpus clustering rather than a rule. Each cluster function
# names its metric through RELATIONAL, so the validated set derives from the same
# declaration the emit sites read: a name absent here is a name error where it is
# emitted, not a directive silently dropped.
const RELATIONAL = (
    duplicate = :duplicate,
    near_duplicate = :near_duplicate,
    library_duplicate = :library_duplicate,
    library_near_duplicate = :library_near_duplicate,
    unnatural = :unnatural,
    low_cohesion = :low_cohesion,
    scattered = :scattered,
    split_audience = :split_audience,
    misplaced = :misplaced,
    distant_definition = :distant_definition,
    unreferenced = :unreferenced,
    reimplementation = :reimplementation,
    back_edge = :back_edge,
    dependency_cycle = :dependency_cycle,
    hub = :hub,
    incoherent_package = :incoherent_package,
    divisible_package = :divisible_package,
)
const RELATIONAL_METRICS = values(RELATIONAL)

# Metric names a directive may name: the active rules plus the relational clone
# metrics. An inline `dendro-ignore` naming anything else warns.
#
# `rules` is typed because the walk over it happens here rather than inside Base's
# collection machinery: an untyped parameter leaves the sound gate analysing the
# comprehension and the append against `Any`, and reading the result widens
# `suppressions` in turn.
function metric_names(rules::Vector{Rule})
    names = Symbol[r.name for r in rules]
    append!(names, RELATIONAL_METRICS)
    return names
end
