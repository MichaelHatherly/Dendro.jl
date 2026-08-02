# Metric reference

```@meta
CurrentModule = Dendro
```

Every metric Dendro reports, its default band, and the page that explains what it
measures. A name in these tables is what an inline `dendro-ignore` accepts, what
`[rules]` switches on or off, and what `[bands]` retunes.

A band is a `(warn, high)` pair. A value at or above `warn` reports `:warn`, a value at
or above `high` reports `:high`, and only `:high` reaches the floor [`errors`](@ref)
gates on. A flag carries no band: it reports at a fixed severity, `:high` for every rule
Dendro ships.

## Per-function scalars

Scored against the band and the corpus percentile, and flagged when either fires. See
[Scoring and metrics](@ref).

| metric | band | default | measures |
| --- | --- | --- | --- |
| `cyclomatic` | 11, 21 | on | decision points in a unit |
| `cognitive_complexity` | 15, 25 | on | decision points weighted by the nesting they sit under |
| `function_length`[^1] | 50, 100 | on | lines in a definition |
| `nesting_depth` | 4, 6 | on | deepest nesting reached |
| `parameter_count`[^1] | 5, 8 | on | parameters in a signature |
| `boolean_complexity` | 4, 6 | on | most `&&`/`||` operators joined into one expression |
| `return_count`[^1] | 4, 8 | opt-in | return points in a definition |
| `npath` | 200, 1000 | opt-in | acyclic execution paths |
| `local_count`[^1] | 10, 15 | opt-in | distinct local names bound |
| `fan_out` | 12, 20 | opt-in | distinct callables invoked |

[^1]: Measures a definition only. Top-level code has no signature and no author-drawn
    boundary, so these say nothing there rather than reading a number against a band
    calibrated on definitions.

## Per-function flags

Presence is the finding. Every one reports `:high`, so every one reaches the gate.

| metric | default | flags |
| --- | --- | --- |
| `identical_operands` | on | `x == x`, `a && a` |
| `duplicate_branches` | on | a conditional whose branches are all identical |
| `empty_body` | on | a definition whose body does nothing |
| `empty_catch` | on | a catch clause that discards the error |
| `stub_marker` | on | a `TODO`/`FIXME`/`XXX`/`HACK` comment |
| `return_in_finally` | on | a `return` inside a finally clause |
| `unused_parameter` | on | a parameter nothing in the unit references |
| `unused_local` | on | a local binding nothing in the unit references |
| `broad_catch` | on | a handler that swallows interrupts and exits |
| `trivial_wrapper` | opt-in | a body that is one delegating call |
| `unreachable_after_jump` | opt-in | code after an unconditional `return`, `break`, or `throw` |
| `shadowed_variable` | opt-in | a local binding hiding an enclosing one |

## Computed across the corpus

Each of these reads the corpus rather than one unit. The band column is empty where the
metric is a flag and always reports `:high`.

| metric | band | default | value is | explained in |
| --- | --- | --- | --- | --- |
| `duplicate` | | on | members of the clone cluster | [Duplicate detection](@ref) |
| `near_duplicate` | | on | the cluster's weakest pairwise similarity, percent | [Duplicate detection](@ref) |
| `reimplementation` | | opt-in | shared rare vocabulary, percent | [Duplicate detection](@ref) |
| `unnatural` | 400, 500 | on | cross-entropy in centibits[^2] | [Scoring and metrics](@ref) |
| `low_cohesion` | 4, 6 | on | independent concerns sharing a file | [Cohesion and placement](@ref) |
| `scattered` | 4, 6 | on | modules the file's units are pulled toward | [Cohesion and placement](@ref) |
| `split_audience` | 3, 5 | on | consumer groups the file serves | [Cohesion and placement](@ref) |
| `misplaced` | 60, 80 | on | coupling landing in one other file, percent | [Cohesion and placement](@ref) |
| `unreferenced` | | on | nothing; the definition is the finding | [Cohesion and placement](@ref) |
| `back_edge` | 85, 95 | on | dominance of the directory pair, percent | [Dependencies and layout](@ref) |
| `dependency_cycle` | 5, 10 | on | files in the cyclic group | [Dependencies and layout](@ref) |
| `hub` | 15, 30 | on | `min(fan_in, fan_out)` over distinct files | [Dependencies and layout](@ref) |
| `incoherent_package` | 50, 75 | opt-in | the directory anchored elsewhere, percent | [Dependencies and layout](@ref) |
| `divisible_package` | 60, 85 | opt-in | the best group's internal ratio, percent | [Dependencies and layout](@ref) |

[^2]: Hundredths of a bit per token, so the default band is 4.00 and 5.00 bits. The
    value is rounded for reporting; the percentile ranks on the unrounded score.

The ten with a band are the relational names `[bands]` accepts. The rest carry no band
to retune.

## Against a library

Both are opt-in and both need a library to compare against. See
[Duplication against a library](@ref).

| metric | default | value is | band |
| --- | --- | --- | --- |
| `library_duplicate` | opt-in | coverage of your function, percent | `:high` for a public whole-function match at or above `library_gate_coverage`, else `:warn` |
| `library_near_duplicate` | opt-in | coverage of your function, percent | always `:warn`, so it never gates |

## Names a project adds

A `[patterns.<name>]` table declares a rule whose name joins this namespace, and a
[`Rule`](@ref) passed to [`analyze`](@ref) does the same. Either suppresses, toggles and
retunes exactly as a built-in does. See [Pattern rules](patterns.md) and
[Custom rules](@ref).

A name Dendro does not know warns wherever it appears, in a `dendro-ignore` directive or
in a `[bands]` or `[rules]` table, so a typo is visible rather than silently disabling a
check.
