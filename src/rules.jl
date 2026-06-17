# Lint rules as data. A rule pairs a metric name with the function that measures
# it, so the active rule set is a value `analyze` carries rather than a fixed set
# of constants. The built-ins below are the default; a caller appends their own.

"""
    Rule

One lint rule. `name` is the metric a finding reports under and the name an
inline `dendro-ignore` directive accepts. `kind` is `:scalar` or `:flag`. A
scalar rule carries its `(warn, high)` `band`; a flag rule carries `nothing`.
`fn` measures one tree or unit:

- scalar `fn(unit, profile, source) -> Int`, scored against the band and the
  corpus percentile.
- flag `fn(tree, profile, source) -> Vector{TreeSitter.Node}`, one `:high`
  finding per returned node.
"""
struct Rule
    name::Symbol
    kind::Symbol
    band::Union{Tuple{Int,Int},Nothing}
    fn::Function
end

# Built-in rules, in report order. Scalar bands are fixed (warn, high) targets,
# so a uniformly-weak codebase has a standard to improve toward rather than only
# its own median. Drawn from common complexity guidance.
const BUILTIN_RULES = Rule[
    Rule(:cyclomatic,      :scalar, (11, 21),  (u, p, s) -> cyclomatic(u.node, p, s)),
    Rule(:function_length, :scalar, (50, 100), (u, p, s) -> function_length(u)),
    Rule(:nesting_depth,   :scalar, (4, 6),    (u, p, s) -> nesting_depth(u.node, p)),
    Rule(:parameter_count, :scalar, (5, 8),    (u, p, s) -> parameter_count(u.node, p)),
    Rule(:empty_body,      :flag,   nothing,   (t, p, s) -> empty_bodies(t, p)),
    Rule(:empty_catch,     :flag,   nothing,   (t, p, s) -> empty_catches(t, p)),
    Rule(:stub_marker,     :flag,   nothing,   (t, p, s) -> stub_markers(t, p, s)),
]

scalar_rules(rules) = Iterators.filter(r -> r.kind == :scalar, rules)
flag_rules(rules) = Iterators.filter(r -> r.kind == :flag, rules)

# Metrics produced by corpus clustering rather than a rule.
const RELATIONAL_METRICS = (:duplicate, :near_duplicate)

# Metric names a directive may name: the active rules plus the relational clone
# metrics. An inline `dendro-ignore` naming anything else warns.
metric_names(rules) = Symbol[(r.name for r in rules)..., RELATIONAL_METRICS...]
