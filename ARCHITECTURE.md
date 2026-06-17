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
  -> per unit: scalar rules; per tree: flag rules
  -> score each reading (absolute band, optional corpus percentile)
  -> mark suppressed findings from inline directives
  -> Findings (a Vector{Finding} that prints as a report)
  -> show / active / gate
```

`analyze` (corpus.jl) is the one entrypoint. It resolves `path` to a corpus (every
profile-resolvable file under a folder, or one file), parses each once, builds a
baseline from that corpus, runs the per-file path above against it for each file,
and appends cross-file duplicates. The active rule set is a value it carries: the
`rules` keyword defaults to `BUILTIN_RULES` and threads through baseline sampling,
per-file scoring, and suppression validation, so a caller extends the checks
without touching the pipeline. The baseline-from-the-corpus step is what makes
relative scoring work with no setup, for a single file as much as a folder: a
file's own functions are the distribution it is scored against.

The `ignore` keyword (gitignore-style patterns, `ignore.jl`) filters the corpus at
collection time, inside `source_files`, before any parsing. Excluded files leave
both the findings and the baseline, so vendored source neither flags nor skews the
percentile. This is corpus-shaping, distinct from `base` scoping, which restricts an
already-built corpus to changed lines.

With `base`, `analyze` scopes to a git diff: it parses the diff of the working tree
against that ref via `changed_ranges` and restricts each file's findings (and the
duplicate clusters, exact and near, through the shared `scope_clusters`) to the
touched line ranges. Nothing else branches the flow.

Duplicate detection crosses the single-file boundary in two passes, both in
`clones.jl`, both syntactic, both comparing only structure with no symbol
resolution. Exact detection (`cluster_duplicates`) hashes every function- or
block-shaped subtree and emits a `:duplicate` `Finding` for each shape shared by
two or more, a whole duplicated function or one block copied between functions,
keeping only the maximal clone. Near-miss detection (`cluster_near_duplicates`)
catches functions that are close but not identical, the copy-paste-then-edit, and
emits `:near_duplicate`.

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
- `metrics.jl` defines the scalar metrics and `severity`: `cyclomatic`,
  `cognitive_complexity`, `function_length`, `nesting_depth`, `parameter_count`,
  `boolean_complexity`, `return_count`. `severity` classifies a value against a
  `(warn, high)` band.
- `flags.jl` defines the presence metrics: `empty_body`/`empty_bodies`,
  `empty_catches`, `stub_markers`, `returns_in_finally`, `trivial_wrappers`,
  `identical_operands`, `duplicate_branches`, `unreachable_statements`, plus the
  helpers for reading a body's real-work count, comparing subtrees by normalised
  text, and collecting the blocks of one conditional chain (`branch_blocks`).
- `rules.jl` defines `Rule` (a metric name, kind, band, and measuring function),
  `BUILTIN_RULES` (the default set, in report order), `OPTIONAL_RULES` (off by
  default), `scalar_rules`/`flag_rules`, and `metric_names` (the names a directive
  may name: the active rules plus the relational clone metrics). The built-in rules
  wrap the metrics.jl/flags.jl functions; a caller's rule wraps their own.
- `baseline.jl` defines `Baseline` over a corpus, `percentile` scoring, and
  `add_samples!`, which samples the active rule set's scalar rules per tree.
- `suppress.jl` defines inline suppression: `Directive`, `DIRECTIVE_RE`,
  `suppressions`, `parse_metrics` (validating against the active rule set's names),
  `is_suppressed`, and `line_of`.

Reporting:

- `report.jl` defines `Location`, `Finding`, `Scan`, `findings_for_tree`,
  `Findings` (the result wrapper, an `AbstractVector{Finding}` with a `show`
  method that renders the report), and `active`. This is where measurement,
  scoring, and suppression meet. Two renderers walk `Findings`: the `show`
  method for `text/plain`, and `github_annotations`, a standalone function (not a
  `show` method) that emits GitHub Actions workflow commands for inline PR
  annotations. Both share `score_suffix`.
- `diff.jl` defines the unified-diff parser (`changed_ranges`, `coalesce_lines`)
  that turns a git diff into per-file line ranges, plus `inrange`/`intersects`.
- `clones.jl` defines both duplicate passes over a shared subtree index. `subtrees`
  hashes every named subtree of a function bottom-up; `subtree_hashes` and
  `node_histogram` derive from it. Exact: `anchor_floor` and `cluster_duplicates`
  bucket function- and block-shaped subtrees by hash, with `subsumed` as the
  maximality filter. Near-miss: `dice` (multiset similarity), `near_miss_edges!`
  (the size-banded characteristic-vector prefilter over `NearestNeighbors`,
  confirmed by Dice), and `cluster_near_duplicates` (union-find over confirmed pairs
  into `:near_duplicate` findings). Included before `corpus.jl`, which calls it.
- `ignore.jl` defines the path filter behind `analyze`'s `ignore` keyword:
  `glob_to_regex` translates one gitignore pattern, `compile_ignores` builds the
  pattern list, `is_ignored` decides a path (last match wins, negation re-includes).
  Pure path logic, no parsing. Included before `corpus.jl`, which calls it.
- `corpus.jl` defines the entrypoint and its machinery: `source_files` (recurse a
  folder for analysable files, pruning ignored paths), `parse_corpus` (parse each
  path once),
  `baseline_from`, `scope_clusters` (the shared diff filter for both duplicate
  passes), and `analyze` (the public entrypoint, orchestrating corpus, baseline,
  per-file findings, exact and near duplicates, and optional diff scoping). It is
  included after `report.jl`, `diff.jl`, and `clones.jl` so everything it calls is
  defined first.

## Core types

`LanguageProfile` (`profile.jl`). Names the tree-sitter node types a language uses
for each construct Dendro measures: function definitions, decision points,
short-circuit operators, nesting constructs, parameter lists, bodies, catch
clauses, comments, name nodes, trivial (no-op) statements, return statements,
finally clauses, and call expressions. Pure data. This is the only place a
language's concrete grammar leaks in. A concept a language lacks stays an empty
set, and a rule reading that concept finds nothing there.

`Rule` (`rules.jl`). One lint check as data: a metric `name`, a `kind` (`:scalar`
or `:flag`), a `(warn, high)` `band` for scalars, and an `fn` that measures one
unit (scalar) or tree (flag). The active set is a `Vector{Rule}` carried by `Scan`
and `analyze`, so checks are a value, not module constants. Built-ins wrap the
metrics.jl/flags.jl functions; a caller's rule wraps their own.

`FunctionUnit` (`units.jl`). One callable definition: the node and its line span.
The granularity at which scalar metrics report.

`Subtree` (`clones.jl`). One named subtree of a function: its structural hash, the
node, and its named-node count. The unit of duplicate detection, which works below
the function as well as at it.

`Location` (`report.jl`). A code site: file, 1-based line, and enclosing unit
name. A `Finding` carries one or more.

`Finding` (`report.jl`). One reported issue over a set of `Location`s: the metric,
the locations, the scalar value (the member count for `:duplicate`, the weakest
pairwise similarity as a percent for `:near_duplicate`, `nothing` for other flags),
the absolute band, the corpus percentile or `nothing`, the kind (`:scalar` or
`:flag`), and `suppressed`. Per-file metrics fire at one location; relational
metrics like `:duplicate` and `:near_duplicate` span several. Suppressed findings
are kept in the vector, not dropped, so they can be counted.

`Findings` (`report.jl`). What `analyze` returns: an `AbstractVector{Finding}`, so
it filters, iterates, and indexes like any vector, with a `show` method that
renders the report. The wrapper exists so display lives on a Dendro-owned type
rather than pirating `show` for `Vector{Finding}`.

`Scan` (`report.jl`). The fixed context for analysing one file: profile, source,
path, the active `rules`, optional baseline, cut percentile, optional diff line
ranges, and the parsed directives. New per-file analysis state belongs here, passed
through the keyword constructor, rather than as a new parameter to `unit_findings!`
or `flag_findings!`. Those signatures stay narrow on purpose, so the functions
Dendro runs over its own source do not grow a parameter-count smell.

`Baseline` (`baseline.jl`). Per-language, per-metric corpus samples, used to place
a reading at a percentile.

`Directive` (`suppress.jl`). One parsed `dendro-ignore`: a scope (a comment line
number, or `:file`) and a metric set (or `nothing` for all metrics).

## Scoring

Every scalar metric carries two independent scores, and a function is flagged when
either trips.

- Absolute: the value against the rule's fixed `(warn, high)` band, classified
  `:ok`, `:warn`, or `:high` by `severity`. Fixed targets, not corpus-derived.
- Relative: the value's percentile against the baseline corpus, flagged when it
  lands at or above the cut (default 0.95). `nothing` when the corpus holds no
  sample for that metric to rank against.

Flag metrics have no distribution. Presence is the finding, always reported at
`:high`.

## Duplicate detection

Both passes share one index. `subtrees` walks a function bottom-up and returns a
`Subtree` (structural hash, node, named-node count) for every named subtree,
stopping at nested callables. Each hash folds a node's type with its children's
hashes in order, so renames and literals drop out (Type-2) while shape stays. The
last entry is the function's own node.

Exact (`cluster_duplicates`) buckets subtrees by `(language, hash)`. Only
function- and block-shaped subtrees anchor a finding: `anchor_floor` admits a
function at `min_size` named nodes and a block at twice that, because a short block
of boilerplate coincides across unrelated code while a small whole function is
already a meaningful unit. Expressions and lone statements never anchor. A bucket of
two or more is a clone class. `subsumed` then drops any anchor whose nearest
enclosing anchor is a clone of at least the same multiplicity, so a duplicated
function is reported once, not again for each block inside it. Multiplicity never
rises going up the tree, so the nearest anchor ancestor is the only one to check.
This is what makes a whole-function clone and a sub-function block clone the same
mechanism at different scales.

Near-miss (`cluster_near_duplicates`) compares whole functions and runs four tiers,
cheapest first, at function granularity so the `Finding`/`Location` model is
unchanged.

1. Index. The sorted multiset of a function's subtree hashes, plus `node_histogram`,
   the characteristic vector. Both come from the shared `subtrees` walk.
2. Exact classes are `cluster_duplicates` above.
3. Confirm. `dice` scores two multisets as `2|a∩b| / (|a|+|b|)`. A pair clears the
   `threshold` (default 0.85) to count as a near-miss.
4. Prefilter. Comparing every pair is O(n²). `near_miss_edges!` densifies the
   histograms over a per-language vocabulary and runs a `NearestNeighbors` radius
   query (L1, `Cityblock`) to propose candidate pairs, which tier 3 confirms. The
   query is never a verdict.

The radius scales with size, because L1 distance grows with function size. Units
bin into size bands by `floor(log2(size))`, and each band queries against itself
and the next band up, so a near-miss whose two functions straddle a power-of-two
boundary is still proposed. Confirmed pairs feed a union-find into clusters. Pairs
with equal digests are dropped: those are exact clones, already reported by tier 2.

Two reasons near-miss is a separate metric, not a smarter `:duplicate`: the exact
path stays near-linear, and an exact match and a 0.85 match are different signals a
reviewer reads differently.

## Suppression

`suppressions` walks the same comment nodes as `stub_markers` and matches
`DIRECTIVE_RE` against each comment's text. A `-file` directive carries `:file`
scope; others carry the comment's line. Named metrics are validated against
`metric_names(rules)`, the active rule set's names plus the relational clone
metrics; an unknown name warns and is dropped.

`is_suppressed(directives, line, metric)` is true when a directive covers the line
(file scope, the same line, or the line directly above) and its metric set is
`nothing` or contains the metric. `unit_findings!` and `flag_findings!` consult it
while building each `Finding` and set the `suppressed` flag. Printing `Findings`
hides suppressed findings and prints a trailing count. `active` returns the
unsuppressed findings for gating.

## Conventions

- Tree-sitter rows are 0-based. `line_of` (in `suppress.jl`) converts to 1-based
  source lines, and `FunctionUnit` stores 1-based lines. Findings are 1-based.
- Metrics are syntactic, with no symbol resolution. Per-file metrics are scoped to
  one file's tree; duplicate detection, exact and near, is what spans files, and it
  still compares only structure.
- Adding a language is data only: a `LanguageProfile` in `profiles.jl` and an
  extension entry in `resolve.jl`. No metric code changes. If a metric needs a
  language special case, the profile is missing a field; add the field.
- A check is a `Rule`: a measuring function plus its metadata. Adding a built-in is
  a `metrics.jl`/`flags.jl` function and a `BUILTIN_RULES` entry. The rule set is a
  value, so a caller adds checks through `analyze`'s `rules` without forking. A rule
  reads node types through the profile, never a raw node-type string, so it stays
  language-agnostic.
- Analysis state travels inside `Scan`, not as new positional parameters.

## Testing

`Pkg.test()` runs under `test/Project.toml`, which carries the language JLLs the
package environment omits, so parsing only works there. `test/dogfood.jl` runs
Dendro on its own `src/`, gated on `active(...)`, and must stay clean: no `:high`
complexity findings (cyclomatic, nesting, length, boolean), no stub markers, no
swallowed errors, no empty bodies, no returns inside a finally clause, no
duplicates exact or near. A change that makes Dendro trip its own metrics is a
signal to fix the code.
