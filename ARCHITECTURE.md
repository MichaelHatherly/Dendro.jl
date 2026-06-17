# Architecture

The source of truth for how Dendro is put together. `AGENTS.md` holds the spirit,
`README.md` the usage, source docstrings the per-symbol contracts. This document
is the map between them. Keep it current: when the structure moves, this file
moves with it in the same change.

## The pipeline

One scan of one file runs the same path every time.

```
source text
  -> parse (TreeSitter, parser chosen by language)
  -> tree
  -> functions(tree, profile)        units to measure
  -> per unit: scalar metrics + flag metrics
  -> score each reading (absolute band, optional corpus percentile)
  -> mark suppressed findings from inline directives
  -> Vector{Finding}
  -> report / active / gate
```

`analyze` runs the whole file. `analyze_diff` runs the same path per changed file
but restricts findings to the touched line ranges. Nothing else branches the
flow.

## Layers

Three layers, low to high. `src/Dendro.jl` includes them in dependency order, and
that order is load-bearing: a type must be defined before the file that uses it.

Resolution and configuration:

- `resolve.jl` maps file extensions to language names and resolves a language to a
  parser. `parser_for` loads `tree_sitter_<lang>_jll` lazily through
  `Base.require`, so Dendro depends on no grammars itself. A missing grammar
  errors with an install hint.
- `profile.jl` defines `LanguageProfile`, pure data with no parser reference. Its
  keyword constructor takes one argument per field and defaults unused node-type
  sets to empty.
- `profiles.jl` holds the `LanguageProfile` instance for each supported language.

Measurement:

- `units.jl` defines `FunctionUnit` (a node plus its 1-based first and last line)
  and `functions(tree, profile)`, which collects every node whose type the profile
  marks as a function.
- `metrics.jl` defines the scalar metrics and their scoring: `cyclomatic`,
  `function_length`, `nesting_depth`, `parameter_count`, the `SCALAR_METRICS`
  tuple that fixes report order, `DEFAULT_BANDS`, and `severity`.
- `flags.jl` defines the presence metrics: `empty_body`, `empty_catches`,
  `stub_markers`, plus the helpers for reading a body's real-work count.
- `baseline.jl` defines `Baseline` over a corpus, percentile scoring, and JSON
  persistence (`build_baseline`, `save_baseline`, `load_baseline`).
- `suppress.jl` defines inline suppression: `Directive`, `METRICS`,
  `DIRECTIVE_RE`, `suppressions`, `is_suppressed`, and `line_of`.

Reporting:

- `report.jl` defines `Finding`, `Scan`, `findings_for_tree`, the top-level
  `analyze`, `report`, and `active`. This is where measurement, scoring, and
  suppression meet.
- `diff.jl` defines `analyze_diff` and the unified-diff parser
  (`changed_ranges`, `coalesce_lines`) that turns a git diff into per-file line
  ranges.

## Core types

`LanguageProfile` (`profile.jl`). Names the tree-sitter node types a language uses
for each construct Dendro measures: function definitions, decision points,
short-circuit operators, nesting constructs, parameter lists, bodies, catch
clauses, comments, name nodes, and trivial (no-op) statements. Pure data. This is
the only place a language's concrete grammar leaks in.

`FunctionUnit` (`units.jl`). One callable definition: the node and its line span.
The granularity at which scalar metrics report.

`Finding` (`report.jl`). One reported issue: file, line, unit name, metric, the
scalar value or `nothing` for a flag, the absolute band, the corpus percentile or
`nothing`, the kind (`:scalar` or `:flag`), and `suppressed`. Suppressed findings
are kept in the vector, not dropped, so they can be counted.

`Scan` (`report.jl`). The fixed context for analysing one file: profile, source,
path, optional baseline, cut percentile, optional diff line ranges, and the parsed
directives. New per-file analysis state belongs here, passed through the keyword
constructor, rather than as a new parameter to `unit_findings!` or
`flag_findings!`. Those signatures stay narrow on purpose, so the functions
Dendro runs over its own source do not grow a parameter-count smell.

`Baseline` (`baseline.jl`). Per-language, per-metric corpus samples, used to place
a reading at a percentile.

`Directive` (`suppress.jl`). One parsed `dendro-ignore`: a scope (a comment line
number, or `:file`) and a metric set (or `nothing` for all metrics).

## Scoring

Every scalar metric carries two independent scores, and a function is flagged when
either trips.

- Absolute: the value against a fixed band in `DEFAULT_BANDS`, classified `:ok`,
  `:warn`, or `:high` by `severity`. Fixed targets, not corpus-derived.
- Relative: the value's percentile against the baseline corpus, flagged when it
  lands at or above the cut (default 0.95). Skipped when no baseline is given.

Flag metrics have no distribution. Presence is the finding, always reported at
`:high`.

## Suppression

`suppressions` walks the same comment nodes as `stub_markers` and matches
`DIRECTIVE_RE` against each comment's text. A `-file` directive carries `:file`
scope; others carry the comment's line. Named metrics are validated against
`METRICS`; an unknown name warns and is dropped.

`is_suppressed(directives, line, metric)` is true when a directive covers the line
(file scope, the same line, or the line directly above) and its metric set is
`nothing` or contains the metric. `unit_findings!` and `flag_findings!` consult it
while building each `Finding` and set the `suppressed` flag. `report` hides
suppressed findings and prints a trailing count. `active` returns the unsuppressed
findings for gating.

## Conventions

- Tree-sitter rows are 0-based. `line_of` (in `suppress.jl`) converts to 1-based
  source lines, and `FunctionUnit` stores 1-based lines. Findings are 1-based.
- Metrics are syntactic, scoped to one file's tree, with no symbol resolution.
- Adding a language is data only: a `LanguageProfile` in `profiles.jl` and an
  extension entry in `resolve.jl`. No metric code changes. If a metric needs a
  language special case, the profile is missing a field; add the field.
- Analysis state travels inside `Scan`, not as new positional parameters.

## Testing

`Pkg.test()` runs under `test/Project.toml`, which carries the language JLLs the
package environment omits, so parsing only works there. `test/dogfood.jl` runs
Dendro on its own `src/`, gated on `active(...)`, and must stay clean: no `:high`
complexity findings, no stub markers, no swallowed errors, no empty bodies. A
change that makes Dendro trip its own metrics is a signal to fix the code.
