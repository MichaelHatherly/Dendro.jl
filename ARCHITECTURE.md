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
  -> build_index(tree, query)        nodes the language query identifies
  -> functions(index)                units to measure
  -> per unit: scalar rules; per index: flag rules
  -> score each reading (absolute band, optional corpus percentile)
  -> mark suppressed findings from inline directives
  -> Findings (a Vector{Finding} that prints as a report)
  -> show / active / gate
```

`analyze` (corpus.jl) is the one entrypoint. It resolves `path` to a corpus (every
profile-resolvable file under a folder, or one file), parses each once, builds a
baseline from that corpus, runs the per-file path above against it for each file,
and appends the corpus-relational findings: cross-file duplicates and naturalness
outliers. The active rule set is a value it carries: the
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
  parser and a query. `parser_for` loads `tree_sitter_<lang>_jll` lazily through
  `Base.require`, so Dendro depends on no grammars itself; `query_for` reads
  `src/queries/<lang>.scm` (located through a `RelocatableFolders` path so it
  survives precompilation) and compiles it against that grammar, caching both
  lazily. A missing grammar errors with an install hint.
- `profile.jl` defines `LanguageProfile`, now just a language `name`. The node types
  it measures live in the language's query, not in this type.
- `profiles.jl` holds the `LanguageProfile` for each supported language, the set
  `analyze` gates a file's extension on.
- `query_index.jl` defines `NodeId`/`nodeid`, `Concept` (the nodes a query tagged
  for one measured construct, plus their ids for O(1) membership), `FunctionUnit`,
  `QueryIndex`, `CONCEPT_NAMES` (the capture names a query may use), and
  `build_index`, which runs a language's query over a tree once and files every
  capture under its concept. Identification lives here: metric code asks whether a
  node was tagged, never matches a node-type string. An unhandled capture name
  throws rather than dropping silently.

Measurement:

- `units.jl` exposes the function units the query identified: `functions(index)`
  returns them (the `index.functions` the query built), and `is_function(node,
  index)` is the no-descend boundary, a node the query tagged `@function`. Both the
  full form (`function ... end`) and the short form (`f(x) = expr`, including the
  `where`/typed unwrapping) are recognised by the language query, so a nested
  short-form def is its own unit and is excluded from its enclosing unit's metrics,
  clones, and tokens.
- `metrics.jl` defines the scalar metrics and `severity`: `cyclomatic`,
  `cognitive_complexity`, `function_length`, `nesting_depth`, `parameter_count`,
  `boolean_complexity`, `return_count`. `severity` classifies a value against a
  `(warn, high)` band.
- `flags.jl` defines the presence metrics: `empty_body`/`empty_bodies`,
  `empty_catches`, `stub_markers`, `returns_in_finally`, `trivial_wrappers`,
  `unreachable_statements`, `identical_operands`, and `duplicate_branches`. Each
  reads the nodes one concept tagged and keeps those a predicate accepts, through the
  shared `filter_nodes`. Plus the helpers: `function_body` (a block child or a
  short-form's right-hand expression), reading a body's real-work count, comparing
  subtrees by normalised text, and collecting the blocks of one conditional chain
  (`branch_blocks`).
- `rules.jl` defines `Rule` (a metric name, kind, band, and measuring function),
  `BUILTIN_RULES` (the default set, in report order), `OPTIONAL_RULES` (off by
  default), `rules_of_kind` (the active rules of one kind), and `metric_names` (the names a directive
  may name: the active rules plus the relational clone metrics). The built-in rules
  wrap the metrics.jl/flags.jl functions; a caller's rule wraps their own.
- `baseline.jl` defines `Baseline` over a corpus, `percentile` scoring, and
  `add_samples!`, which samples the active rule set's scalar rules over one file's
  index.
- `suppress.jl` defines inline suppression: `Directive`, `DIRECTIVE_RE`,
  `suppressions`, `parse_metrics` (validating against the active rule set's names),
  `is_suppressed`, and `line_of`.

Reporting:

- `report.jl` defines `Location`, `Finding`, `Scan`, `findings_for`,
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
- `naturalness.jl` defines cross-entropy scoring, the other corpus-relational pass.
  `token_stream` reduces a function to leaf tokens (identifier and literal text
  abstracted, the grammar's anonymous tokens kept); `build_model` counts a per-language
  trigram model with add-one smoothing; `cross_entropy` scores a function's surprise
  under that model in bits per token; `cluster_unnatural` emits an `:unnatural` finding
  per function, carrying both an absolute cross-entropy band and the corpus percentile,
  skipping a language whose corpus is below `MIN_CORPUS_TOKENS`. A surprising function
  reads as unidiomatic, which correlates with bugs. Structure only, no symbol
  resolution; within one language. Included before `corpus.jl`, which calls it.
- `ignore.jl` defines the path filter behind `analyze`'s `ignore` keyword:
  `glob_to_regex` translates one gitignore pattern, `compile_ignores` builds the
  pattern list, `is_ignored` decides a path (last match wins, negation re-includes).
  Pure path logic, no parsing. Included before `corpus.jl`, which calls it.
- `corpus.jl` defines the entrypoint and its machinery: `source_files` (recurse a
  folder for analysable files, pruning ignored paths), `parse_corpus` (parse each
  path once and build its query index into a `Vector{ParsedFile}`),
  `baseline_from`, `scope_clusters` (the shared diff filter for the relational
  passes), and `analyze` (the public entrypoint, orchestrating corpus, baseline,
  per-file findings, exact and near duplicates, naturalness, and optional diff
  scoping). It is included after `report.jl`, `diff.jl`, `clones.jl`, and
  `naturalness.jl` so everything it calls is defined first.

## Core types

`LanguageProfile` (`profile.jl`). Just a language `name`. The set of profiles is
what `analyze` gates a file's extension on; the node types each language uses live
in its query, not here.

`QueryIndex` (`query_index.jl`). One tree's identified nodes: the `functions` units
and `function_ids` (the no-descend boundary), plus one `Concept` per measured
construct (decision points, short-circuit operators, nesting, parameters, bodies,
catches, comments, names, trivial statements, returns, finally clauses, calls,
binary expressions, conditionals, terminals, short-form definitions). A `Concept`
holds the tagged nodes in source order and a `Set{NodeId}` for membership. Built
once per file by `build_index`: the constructor starts every concept empty, then
`dispatch!` files each capture by name and throws on a name outside `CONCEPT_NAMES`.
The suite checks every query's capture names against that set. This is the only
place a language's concrete grammar leaks in: a construct a language lacks has no
pattern, so its concept is empty and a rule reading it finds nothing.

`Rule` (`rules.jl`). One lint check as data: a metric `name`, a `kind` (`:scalar`
or `:flag`), a `(warn, high)` `band` for scalars, and an `fn` that measures one
unit (scalar) or the file's index (flag). The active set is a `Vector{Rule}` carried by `Scan`
and `analyze`, so checks are a value, not module constants. Built-ins wrap the
metrics.jl/flags.jl functions; a caller's rule wraps their own.

`ParsedFile` (`parsed_file.jl`). One parsed corpus file: language, source, path,
tree-sitter tree, the query index, and inline suppression directives. `parse_corpus` builds a
`Vector{ParsedFile}`, and the baseline, per-file scoring, and clustering passes all
read from it, so no file is parsed twice. Concrete in every field, so the relational
passes dispatch statically over it rather than through `getproperty(::Any)`.

`FunctionUnit` (`units.jl`). One callable definition: the node and its line span.
The granularity at which scalar metrics report.

`Subtree` (`clones.jl`). One named subtree of a function: its structural hash, the
node, and its named-node count. The unit of duplicate detection, which works below
the function as well as at it.

`AnchorEntry` (`clones.jl`). One indexed anchor in exact-clone detection: a
function- or block-shaped subtree large enough to count, with its language,
structural hash, node, location, and suppression flag. `cluster_duplicates` builds a
vector of these and `subsumed` reads it, a concrete record so the maximality filter
stays type-stable.

`Scope` (`corpus.jl`). The diff-scoped view's data: the git toplevel `root` and the
changed line ranges per file relative to it (`Dict{String, Vector{UnitRange{Int}}}`).
`analyze` builds one from `base`'s diff, and `scope_clusters` filters cluster findings
to it. A concrete record, so the diff-scoping passes dispatch statically rather than
over an ad-hoc NamedTuple.

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

`Scan` (`report.jl`). The fixed context for analysing one file: the query index,
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
- Adding a language is data only: a query in `src/queries/<lang>.scm`, a
  `LanguageProfile` entry in `profiles.jl`, and an extension entry in `resolve.jl`.
  No metric code changes. If a metric needs a language special case, the query is
  missing a capture; add the pattern.
- A check is a `Rule`: a measuring function plus its metadata. Adding a built-in is
  a `metrics.jl`/`flags.jl` function and a `BUILTIN_RULES` entry. The rule set is a
  value, so a caller adds checks through `analyze`'s `rules` without forking. A rule
  reads nodes through the index's concepts, never a raw node-type string, so it stays
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
