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
       (+ scopes query: resolve each reference to its in-file definition)
  -> functions(index)                units to measure
  -> per unit: scalar rules; per index: flag rules
  -> score each reading (absolute band, optional corpus percentile)
  -> mark suppressed findings from inline directives
  -> Findings (a Vector{Finding} that prints as a report)
  -> show / active / gate
```

`analyze` (corpus.jl) is the one entrypoint. It resolves one or more paths to a
corpus (every profile-resolvable file under each folder, or a named file), parses
each once, builds a baseline from that corpus, runs the per-file path above
against it for each file,
and appends the corpus-relational findings: cross-file duplicates, naturalness
outliers, low-cohesion files, misplaced units, scattered files, and unreferenced
private definitions. The active rule set is a value it carries: the
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
  lazily. A missing grammar errors with an install hint. `scopes_query_for` reads the
  optional `src/queries/<lang>.scopes.scm` the same way, returning `nothing` for a
  language that ships none.
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
  throws rather than dropping silently. Given a scopes query, `build_index` runs a
  second pass through `resolve_bindings!` and fills `index.bindings`.
- `bindings.jl` defines tier-1 lexical scope resolution: `ScopeEntry`, the helpers
  `owning_scope` and `lookup_definition`, and
  `resolve_bindings!`, which runs a language's scopes query over a tree and binds
  each `@reference` to the nearest enclosing `@definition` of its name. Function,
  type, and macro names (`HOISTED_KINDS`) bind in the enclosing scope so a sibling
  reference resolves to them. Scope membership is geometric, from byte ranges.
  Single file, no symbol resolution across files, no types, no dispatch. Included
  after `query_index.jl`, whose `NodeId` it uses.

Measurement:

- `units.jl` exposes the function units the query identified: `functions(index)`
  returns them (the `index.functions` the query built), and `is_function(node,
  index)` is the no-descend boundary, a node the query tagged `@function`. Both the
  full form (`function ... end`) and the short form (`f(x) = expr`, including the
  `where`/typed unwrapping) are recognised by the language query, so a nested
  short-form def is its own unit and is excluded from its enclosing unit's metrics,
  clones, and tokens.
- `graph_edges.jl` defines what a within-file binding edge is, the relation cohesion and
  scattering share. `containing_unit` finds the innermost unit spanning a byte range;
  `binding_groups` reads `index.bindings` into the groups of local units that share a
  definition, dropping a binding referenced by more than `COHESION_UBIQUITY` of the
  file's units. The corpus graph folds these into `within_edges`. Included after
  `units.jl` (it calls `functions`), before `corpus_graph.jl` reads it.
- `metrics.jl` defines the scalar metrics and `severity`: `cyclomatic`,
  `cognitive_complexity`, `function_length`, `nesting_depth`, `parameter_count`,
  `boolean_complexity`, `return_count`, and `npath` (NPath complexity, a recursion
  that dispatches on construct family from the query and saturates at `NPATH_CAP`).
  `severity` classifies a value against a `(warn, high)` band.
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
  hashes every named subtree of a function bottom-up. Exact: `anchor_floor` and `cluster_duplicates`
  bucket function- and block-shaped subtrees by hash, with `subsumed` as the
  maximality filter. Near-miss: `clone_features` (a unit's pre-order hash sequence,
  histogram, digest, and size from one walk), `lcs_length`/`clone_similarity` (the
  order-aware LCS verdict), `near_miss_edges!` (the size-banded characteristic-vector
  prefilter over `NearestNeighbors`, confirmed by `pair_similarity`), and
  `cluster_near_duplicates` (union-find over confirmed pairs into `:near_duplicate`
  findings). Included before `corpus.jl`, which calls it.
- `naturalness.jl` defines cross-entropy scoring, the other corpus-relational pass.
  `token_stream` reduces a function to leaf tokens (identifier and literal text
  abstracted, the grammar's anonymous tokens kept); `build_model` counts a per-language
  trigram model with add-one smoothing; `interpolated_cross_entropy` scores a
  function's surprise under `λ·P_global + (1-λ)·P_cache`, the corpus model blended
  with a per-file cache (`file_caches`) so a function is read against its own file's
  idiom (Tu et al.), with `cross_entropy` the global-only case at `λ = 1`;
  `cluster_unnatural` emits an `:unnatural` finding per function, carrying both an
  absolute cross-entropy band and the corpus percentile, skipping a language whose
  corpus is below `MIN_CORPUS_TOKENS`. A surprising function
  reads as unidiomatic, which correlates with bugs. Structure only, no symbol
  resolution; within one language. Included before `corpus.jl`, which calls it.
- `linkage.jl` defines corpus-wide symbol resolution. `corpus_symbols` builds a
  `SymbolTable` of every top-level definition across the corpus, each carrying its
  enclosing module path (from a per-language `@module` capture, so a nested module is
  distinguished from the file root); `unbound_references` collects the references the
  per-file resolver left unbound. `Linkage`/`LINKAGES` carry how a
  language lets one file see another's names: `splice_resolve` maps a Julia `include`
  to a corpus file, `visible_defs` groups files into shared namespaces by an inclusion
  union-find and returns each file's cross-file candidates, and `corpus_references` is the
  shared resolver yielding every cross-file reference with its candidates (the corpus graph
  and the reachability pass both read it). The `:package` model (Java) unions import
  visibility with `package_visible`, the same-directory types a package resolves without an
  import, so a package-private class reference resolves. `Linkage.is_public` and the
  per-language predicates (`export_public`, `underscore_public`, `capitalized_public`,
  `modifier_public`) decide public-API membership, and `public_surface` gives each file its
  export set, the file's own for an import model, the inclusion component's for a splice.
  The convention predicates read a `CorpusDef`'s name; `modifier_public` reads its
  `visibility`, set by `def_visibility` from a grammar-specific modifier (Rust `pub`, a
  C/C++ `static` function, a Ruby/Java/PHP `private` method, a package-private Java class).
  Reuses the `bindings.jl` capture walk and the `clones.jl` union-find. Included after
  `naturalness.jl`.
- `corpus_graph.jl` defines the corpus unit graph, the one structure the three placement
  passes read. `build_corpus_graph` resolves every unbound reference against the symbol
  table through `visible_defs`, recording weighted unit-to-unit `edges` and per-unit file
  mass; a reference matching `k` definitions splits `1/k`, and a definition referenced by
  more than `CORPUS_UBIQUITY` of the units is dropped as cross-cutting. It also folds each
  file's within-file binding edges (`within_binding_edges` over `binding_groups`) into
  `within_edges`. `adjacency(graph; within)` builds the undirected neighbour-weight view,
  cross-file alone or with the within edges folded in; `communities` runs one level of
  modularity optimisation (Louvain local moving) over it for the neighbourhoods, and
  `components` flood-fills the within view restricted to one file's nodes for cohesion.
  Included after `linkage.jl`.
- `placement.jl` defines cross-file placement, the fourth corpus-relational pass.
  `own_affinity` reads each unit's same-file coupling from `index.bindings`;
  `community_plurality` finds the file each community is anchored in; `cluster_misplaced`
  emits a `:misplaced` finding per envious unit, scored by the share of its whole
  coupling landing in the one other file it leans toward most, carrying the absolute
  `MISPLACED_BAND` and the corpus percentile, gated by the community anchor. Included
  before `corpus.jl`, which calls it.
- `scattered.jl` defines cross-file scattering, the file-level companion to
  `:low_cohesion`. `cluster_scattered` reads `communities(adjacency(graph; within = true))`,
  the corpus graph with each file's within-file binding edges folded in, so `communities`
  sees a file's own cohesion and a file's units land in communities. It emits a
  `:scattered` finding per file, scored by the count of distinct communities its units
  occupy whose plurality anchor is another file, carrying the absolute `SCATTERED_BAND`
  and the corpus percentile. Included after `placement.jl`.
- `unreferenced.jl` defines dead-code detection by reachability, not the corpus graph but
  a dedicated reference graph over `table.defs` that keeps non-unit targets and discounts
  no cross-cutting utility. `reach_graph` builds the forward edges (within-file bindings
  and `corpus_references`, each attributed to its enclosing top-level definition by
  `enclosing_def`) and the root set (declared-public definitions and those referenced from
  top-level code); `reachable` walks it breadth-first. `cluster_unreferenced` emits an
  `:unreferenced` finding per unreached definition, suppressible inline. Reads `linkage.jl`
  for `corpus_references` and the public surface. Included after `scattered.jl`.
- `cohesion.jl` defines within-file cohesion. `cluster_low_cohesion` reads the within
  view of the corpus graph, `components(adjacency(graph; within = true), file_nodes)`:
  cross-file edges never join one file's nodes, so the components restricted to a file are
  its independent concerns. `component_reps` picks one representative unit per component
  (earliest line first). The finding carries the absolute `LOW_COHESION_BAND` on the
  component count and the corpus percentile, skipping a language with no scopes query, a
  file below `MIN_COHESION_UNITS`, and a corpus below `MIN_COHESION_FILES` for the
  percentile. The LCOM4 reading of independent concerns cohabiting. Binding-keyed but
  still syntactic, within one file. Included after `scattered.jl`, since its signature
  names `CorpusGraph`.
- `ignore.jl` defines the path filter behind `analyze`'s `ignore` keyword:
  `glob_to_regex` translates one gitignore pattern, `compile_ignores` builds the
  pattern list, `is_ignored` decides a path (last match wins, negation re-includes).
  Pure path logic, no parsing. Included before `corpus.jl`, which calls it.
- `corpus.jl` defines the entrypoint and its machinery: `source_files` (recurse a
  folder for analysable files, pruning ignored paths), `parse_corpus` (parse each
  path once and build its query index into a `Vector{ParsedFile}`),
  `baseline_from`, `scope_clusters` (the shared diff filter for the relational
  passes), and `analyze` (the public entrypoint, orchestrating corpus, baseline,
  per-file findings, exact and near duplicates, naturalness, then the corpus graph and
  the three passes that read it, low cohesion, cross-file placement, scattering, and
  optional diff scoping). It is included after `report.jl`, `diff.jl`, `clones.jl`,
  `naturalness.jl`, `linkage.jl`, `corpus_graph.jl`, `placement.jl`, `scattered.jl`, and
  `cohesion.jl` so everything it calls is defined first.

## Core types

`LanguageProfile` (`profile.jl`). Just a language `name`. The set of profiles is
what `analyze` gates a file's extension on; the node types each language uses live
in its query, not here.

`QueryIndex` (`query_index.jl`). One tree's identified nodes: the `functions` units
and `function_ids` (the no-descend boundary), plus one `Concept` per measured
construct (decision points, short-circuit operators, nesting, parameters, bodies,
catches, comments, names, trivial statements, returns, finally clauses, calls,
binary expressions, binary operators, conditionals, terminals, short-form
definitions, and the NPath construct families: loops, switches, ternaries, tries,
cases). A `Concept`
holds the tagged nodes in source order and a `Set{NodeId}` for membership. Built
once per file by `build_index`: the constructor starts every concept empty and
builds a `by_name` table mapping each capture to its concept, then `dispatch!` files
each capture through that table and throws on a name outside `CONCEPT_NAMES`.
The suite checks every query's capture names against that set. This is the only
place a language's concrete grammar leaks in: a construct a language lacks has no
pattern, so its concept is empty and a rule reading it finds nothing. `QueryIndex`
also carries `bindings`, a `Dict{NodeId, NodeId}` from each reference to the in-file
definition it resolves to, empty unless `build_index` was given a scopes query.

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
to it. Several scanned roots still resolve to one toplevel and one repo-wide diff,
since findings carry absolute paths that `relpath` against `root` regardless of root. A concrete record, so the diff-scoping passes dispatch statically rather than
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

1. Index. `clone_features` takes one `subtrees` walk per function and returns its
   pre-order subtree-hash sequence (for the verdict), its `node_histogram`
   characteristic vector (for the prefilter), its exact digest, and its size.
2. Exact classes are `cluster_duplicates` above.
3. Confirm. `clone_similarity` scores two sequences by longest common subsequence as
   `|LCS| / max(|a|, |b|)`, after NiCad. A pair clears the `threshold` (default 0.85)
   to count as a near-miss. The LCS is order-aware: a reordering of the same subtrees,
   or a short fragment inside a long function, scores low where a multiset overlap
   would not. A size-ratio prefilter skips the O(n*m) LCS on mismatched lengths.
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

## Within-file cohesion

`cluster_low_cohesion` reads whether a file's functions group by usage. The substrate
is tier-1 lexical binding (`bindings.jl`): a per-language scopes query
(`src/queries/<lang>.scopes.scm`) tags scope regions, definitions, and references,
and `resolve_bindings!` binds each reference to the nearest enclosing definition of
its name, hoisting function, type, class, and macro names to the enclosing scope so a
sibling reference resolves to them. Linking on a resolved binding rather than a
shared identifier string is what drops the `x`/`i`/`T` and imported-name noise a
string graph carries: a local in one function and a same-named local in another are
different bindings, and an external name resolves to nothing.

The unit graph is the corpus graph's within view. `binding_groups` (`graph_edges.jl`)
reads `index.bindings`: two units link when they reference a common file-local binding,
and a binding referenced by more than `COHESION_UBIQUITY` of the units is cross-cutting (a
file-wide utility) and links nothing, so it cannot fold genuine concerns into one
component. `build_corpus_graph` folds these into `within_edges`, and
`cluster_low_cohesion` runs `components` over `adjacency(graph; within = true)` restricted
to one file's nodes: cross-file edges never join those nodes, so the components are the
file's independent concerns. The component count is the score: one component is a cohesive
file, several are independent concerns cohabiting, the LCOM4 reading. The finding's
locations are one representative function per component, earliest line first.

Like naturalness, cohesion carries both scores, fired when either trips: the absolute
`LOW_COHESION_BAND` on the component count, set above an idiomatic corpus's spread,
and the corpus percentile across the scored files. Every supported language ships a
scopes query, so cohesion runs everywhere Dendro parses; a language without one would
be skipped rather than reported as all-isolated. The ceiling is honest: name
resolution gives def-site linkage, never dispatch resolution, so an edge is "these two
functions reference this file-local name," not "these two dispatch to the same
method." With no field resolution, the edge is call linkage, not shared-field
cohesion, so a file that is one class reads only its method-to-method calls. Java is
the extreme, every file a single class. Most cohesion signal lives below that line.

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
  missing a capture; add the pattern. A `src/queries/<lang>.scopes.scm` is optional;
  with it the language gains binding resolution and cohesion, without it both skip.
- A check is a `Rule`: a measuring function plus its metadata. Adding a built-in is
  a `metrics.jl`/`flags.jl` function and a `BUILTIN_RULES` entry. The rule set is a
  value, so a caller adds checks through `analyze`'s `rules` without forking. A rule
  reads nodes through the index's concepts, never a raw node-type string, so it stays
  language-agnostic.
- Analysis state travels inside `Scan`, not as new positional parameters.

## Testing

`Pkg.test()` runs under `test/Project.toml`, which carries the language JLLs the
package environment omits, so parsing only works there. The suite is
[TestItemRunner](https://github.com/julia-vscode/TestItemRunner.jl): `runtests.jl`
is one `@run_package_tests` call, and each check is a self-contained `@testitem`
tagged by area (`:metrics`, `:clones`, `:jet`, …). Items run in their own module,
so each imports what it uses; `Dendro` and `Test` are auto-imported. Shared
helpers and the language-fixture tables live in one `@testmodule Fixtures`
(`test/setup.jl`), reached qualified, e.g. `Fixtures.idx(:julia, src)`.

`test/dogfood.jl` runs Dendro on its own `src/`, gated on `active(...)`, and must
stay clean: no `:high` complexity findings (cyclomatic, nesting, length, boolean),
no function so unnatural or file so low in cohesion it trips the absolute band, no
stub markers, no swallowed errors, no empty bodies, no returns inside a finally
clause, no duplicates exact or near. `:unnatural` and `:low_cohesion` are checked on
their absolute band only; their percentile flags the top of any distribution and is
not part of this deterministic gate. A change that makes Dendro trip its own metrics
is a signal to fix the code.

`test/jet.jl` is the `:jet` item: basic-mode JET is a zero-tolerance gate on every
Julia version, sound mode and the optimization analyzer are ratcheted at
`SOUND_LIMIT`/`OPT_LIMIT` (pinned to one Julia version, lowered when a count drops).
