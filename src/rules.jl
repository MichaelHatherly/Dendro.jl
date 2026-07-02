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
- flag `fn(index) -> Vector{TreeSitter.Node}`, one `:high` finding per returned
  node.
"""
struct Rule
    name::Symbol
    kind::Symbol
    band::Union{Tuple{Int, Int}, Nothing}
    fn::Function
end

"""
    BUILTIN_RULES :: Vector{Rule}

The default rule set, in report order. Scalar bands are fixed `(warn, high)`
targets, so a uniformly-weak codebase has a standard to improve toward rather than
only its own median. Drawn from common complexity guidance. Pass `rules` to
[`analyze`](@ref) to extend or replace them.
"""
const BUILTIN_RULES = Rule[
    Rule(:cyclomatic, :scalar, (11, 21), (u, i) -> cyclomatic(u.node, i)),
    Rule(:cognitive_complexity, :scalar, (15, 25), (u, i) -> cognitive_complexity(u.node, i)),
    Rule(:function_length, :scalar, (50, 100), (u, i) -> function_length(u)),
    Rule(:nesting_depth, :scalar, (4, 6), (u, i) -> nesting_depth(u.node, i)),
    Rule(:parameter_count, :scalar, (5, 8), (u, i) -> parameter_count(u.node, i)),
    Rule(:boolean_complexity, :scalar, (4, 6), (u, i) -> boolean_complexity(u.node, i)),
    Rule(:identical_operands, :flag, nothing, identical_operands),
    Rule(:duplicate_branches, :flag, nothing, duplicate_branches),
    Rule(:empty_body, :flag, nothing, empty_bodies),
    Rule(:empty_catch, :flag, nothing, empty_catches),
    Rule(:stub_marker, :flag, nothing, stub_markers),
    Rule(:return_in_finally, :flag, nothing, returns_in_finally),
    Rule(:unused_parameter, :flag, nothing, unused_parameters),
    Rule(:unused_local, :flag, nothing, unused_locals),
]

"""
    OPTIONAL_RULES :: Vector{Rule}

Rules a caller can opt into but that are off by default: `return_count` needs
per-project band tuning, `trivial_wrapper` has a higher false-positive rate,
`unreachable_after_jump` flags code after an unconditional jump, and `npath` grows
multiplicatively so its band wants per-project tuning. Use them with
`analyze(path; rules = [BUILTIN_RULES; OPTIONAL_RULES])`.
"""
const OPTIONAL_RULES = Rule[
    Rule(:return_count, :scalar, (4, 8), (u, i) -> return_count(u.node, i)),
    Rule(:trivial_wrapper, :flag, nothing, trivial_wrappers),
    Rule(:unreachable_after_jump, :flag, nothing, unreachable_statements),
    Rule(:npath, :scalar, (200, 1000), (u, i) -> npath(u.node, i)),
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
    unnatural = :unnatural,
    low_cohesion = :low_cohesion,
    scattered = :scattered,
    misplaced = :misplaced,
    unreferenced = :unreferenced,
)
const RELATIONAL_METRICS = values(RELATIONAL)

# Metric names a directive may name: the active rules plus the relational clone
# metrics. An inline `dendro-ignore` naming anything else warns.
metric_names(rules) = Symbol[(r.name for r in rules)..., RELATIONAL_METRICS...]
