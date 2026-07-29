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

`analyze` (analyze.jl) is the one entrypoint. It resolves one or more paths to a corpus
(every profile-resolvable file under each folder, or a named file), parses each once,
builds a baseline from that corpus, runs the per-file path above against it for each
file, and appends the corpus-relational findings: cross-file duplicates, naturalness
outliers, low-cohesion files, misplaced units, scattered files, unreferenced private
definitions, files serving disjoint audiences, dependencies running against a directory
pair's grain, dependency cycles, hub files, and, when the config enables it, incoherent
packages. The active rule set is a value it carries, resolved from a
`Config` (see Configuration)
unless the `rules` keyword overrides it, and it threads through baseline sampling, per-file
scoring, and suppression validation, so a caller extends the checks without touching the
pipeline. The baseline-from-the-corpus step is what makes relative scoring work with no
setup, for a single file as much as a folder: a file's own functions are the
distribution it is scored against.

Above that per-file path sits the corpus resolution the relational passes share.
`corpus_symbols` indexes every top-level definition and `resolve_linkage` resolves the
corpus against it once, yielding the four readings six passes want: what each file can
see across the boundary, the references that visibility admits, who consumes each
definition, and each file's public surface.

```
corpus files
  -> corpus_symbols          top-level definitions across the corpus
  -> resolve_linkage         one ResolvedLinkage: visible, references,
                             consumers, surface
       -> build_corpus_graph   units, cross-cutting references dropped
       -> build_file_graph     files, every resolved reference kept
```

`analyze` hoists that one `ResolvedLinkage` and hands it to both graphs and to every pass
that reads references, reachability, the audience pass, the hub proposal, and the back-edge
reference sites among them, so a scan resolves the corpus once rather than six times. It
travels through the keyword slot the bare visibility map used to occupy, so no pass grew a
parameter to take it. Cohesion, placement,
scattering, reachability, and the opt-in `:incoherent_package` run over the unit graph;
`:back_edge`, `:dependency_cycle`, `:hub` and the opt-in `:divisible_package` run over the
one file graph, the substrate
for the rules that read the corpus as files depending on files. It is built before the
clone passes report, since they rank their clusters by distance in its directory
contraction.

The `ignore` keyword (gitignore-style patterns, `ignore.jl`) filters the corpus at
collection time, inside `source_files`, before any parsing. Excluded files leave
both the findings and the baseline, so vendored source neither flags nor skews the
percentile. This is corpus-shaping, distinct from `base` scoping, which restricts an
already-built corpus to changed lines.

With `base`, `analyze` scopes to a git diff: it parses the diff of the working tree
against that ref via `changed_ranges` and restricts each file's findings (and the
duplicate clusters, exact and near, through the shared `scope_clusters`) to the
touched line ranges. Nothing else branches the flow.

## Parallelism

Each fan-out runs across threads when its own item count, files, candidate clone
pairs, or naturalness units, clears a size floor (`PARALLEL_MIN`) and Julia runs
with more than one thread. Below the floor, or single-threaded, that fan-out runs
serially. The floor is per fan-out, not per run: a small diff or single-file gate
pays no task overhead in the per-file passes, but a single file with enough
functions still fans its pair- and unit-level passes out. `src/parallel.jl` holds
the primitives: `parallel_map!` writes one value per item into a preallocated
indexed vector, `parallel_flatmap` concatenates per-item vectors in index order,
and `parallel_chunks` runs a worker per chunk, giving each its own state (a parser
pool, a partial baseline) and returning the states in chunk order. All split work
round-robin, so a large file or function does not skew a chunk, and a failed task
rethrows its own exception, so errors surface identically to the serial path.

The parallel fronts, in cost order: the near-miss LCS confirmation
(`near_miss_edges!`, the dominant pass), the cross-file symbol resolution
(`corpus_symbols`, `visible_defs`, `corpus_references`, `own_affinity`), naturalness
(tokenizing, the per-file cache models, and cross-entropy scoring), and the three
per-file steps at the front of `analyze`, parsing (`parse_corpus`, one stateful
`TreeSitter.Parser` per chunk), baseline sampling (`baseline_from`, per-chunk partials
merged), and per-file scoring. The serial remainders are the corpus-global joins, the
inclusion-component and clone union-finds and community detection, and the naturalness
global model, a trigram-dict reduction where a parallel merge would not pay.

Two invariants hold it together. The lazy per-language caches (`parser_for` and the
query caches in `resolve.jl`) are guarded by `CACHE_LOCK`, so a concurrent
first-touch is safe from any fan-out; `warm_languages` fills them before the parse
so no task pays a JLL load or query compile mid fan-out. Every parallel path writes
into a preallocated indexed vector, folds in index order through `parallel_flatmap`,
or merges then sorts, so the findings are byte-identical to the serial path at any
thread count. That
determinism is tested in `test/parallel.jl`; the dogfood gate and the benchmark trend
both rely on it, and the benchmark suite pins itself to one thread.

## Configuration

The bands a finding is judged against are tunable, the cascade resolved in
`config.jl`. `Config` is immutable: the percentile `cut`, a scalar-band override dict,
one band field per relational metric, in `RELATIONAL_BANDS` order since the constructor is
positional and every band shares a type, a rule on/off override dict, and the three
clone-detection thresholds. `discover_config(roots)` accumulates each layer's overrides
starting from the built-in defaults (the relational band consts, `DEFAULT_CUT`, the
clone consts, empty override dicts), overlaying a user-global
`~/.config/dendro/config.toml` and the repo `.dendro.toml` found at `git_toplevel`,
then builds one `Config`. Each layer is `apply_toml!`, which touches only the keys
present and warns on an unknown one. `analyze` then resolves without mutating: `cfg =
discover_config(roots)` unless a `config` is passed, an explicit `cut` resolves over
`cfg.cut` (`something(cut, cfg.cut)`), and `resolve_rules(cfg)` builds the active rule
set, dropping disabled built-ins, adding enabled optionals, and rebanding each scalar
rule from `cfg.bands`. The relational bands thread into the `cluster_*` calls. Reading
the config rather than mutating it means no copy is needed, even when a caller passes
their own. Discovery is source precedence, never spatial: one corpus, one baseline,
one set of bands per run, since the percentile half is corpus-global.

`main.jl` is the CLI behind `julia -m Dendro` and the `dendro` app (`[apps.dendro]` in
`Project.toml`, wired through `@main`). It parses argv into `CLIOptions`, discovers the
config, runs `analyze`, prints the report or GitHub annotations, and returns an exit
code, 1 under `--check` when anything is reported. It reads the same cascade, so a repo
with a `.dendro.toml` gets its bands with no flags passed.

## Gating

`analyze` answers triage, "where to look", and ranks by corpus percentile, so its
result is never empty: the worst-N% always exists. A CI gate needs the opposite, a
pass/fail signal that is satisfiable and stable. `errors` (`gate.jl`) is that view:
the deterministic floor, every finding at the `:high` absolute band, which is
high-band scalars plus all flags (flags are always `:high`). Percentile-only
findings carry `:ok`/`:warn` and drop out, so the floor never fails on rank alone.
Inline `dendro-ignore` directives apply first, so a suppressed finding lifts the
gate. Assert `isempty(errors(path))` in a test and every package's `Pkg.test()`
gates on Dendro for free. Like `analyze`, `errors` resolves a `Config` (see
Configuration), so a repo `.dendro.toml` that retunes a band or toggles a rule reaches
the gate, and it scores the working tree and the `since` base against the same config,
so a retune never reads as a regression on its own.

With `since`, a git ref, `errors` becomes a ratchet: the floor at the working tree
minus the floor at that ref. `base_floor_counts` materialises the base by `git
archive`ing only the scanned paths at `since` into a tempdir (no worktree or index
mutation), analyzing that, and counting each finding's `fkey`, the metric paired with
its location set as `(repo-relative file, unit)`. `ratchet` then walks the HEAD floor
and emits a finding only when the base multiset has no remaining count for its key, so
a new violation emits while a pre-existing one, even on a touched line, is matched and
dropped. Keys are line-independent, so unrelated edits that move code do not
manufacture deltas; renames key as new, the safe direction for a gate. This is the
regression measure the spatial diff is not.

This is distinct from the spatial diff. `analyze(; base)` filters findings to
touched lines and feeds the annotation path; it is spatial, not a regression
measure. `errors` is the gate.

Duplicate detection crosses the single-file boundary in two passes, both in
`clones.jl`, both syntactic, both comparing only structure with no symbol
resolution. Exact detection (`cluster_duplicates`) hashes every function- or
block-shaped subtree and emits a `:duplicate` `Finding` for each shape shared by
two or more, a whole duplicated function or one block copied between functions,
keeping only the maximal clone. Near-miss detection (`cluster_near_duplicates`)
catches functions that are close but not identical, the copy-paste-then-edit, and
emits `:near_duplicate`.

A third pass, opt-in and in `reimplementation.jl`, reads vocabulary where the other
two read structure: a helper rewritten with a different shape shares no subtrees
with the original but keeps its callee names and identifier words. Each function's
terms (callee names, namespaced apart, plus identifier subtokens) are weighted by
scan-time corpus IDF; an inverted index over rare terms proposes pairs, and a pair
whose IDF-weighted Jaccard clears the config's threshold emits `:reimplementation`,
unless a gate claims it first: already reported by a clone pass, equal digest, same
name, one calling the other, or a 2:1 size mismatch. Still name-based and
corpus-derived, no types and no pretrained model, and off by default because
vocabulary evidence is proposal-strength.

## Layers

Three layers, low to high. `src/Dendro.jl` includes them in dependency order, and
that order is load-bearing: a type must be defined before the file that uses it.

Resolution and configuration:

- `resolve.jl` maps file extensions to language names and resolves a `LanguageProfile`
  to a parser and a query. `language_grammar` loads a profile's grammar: a `grammar`
  naming a directory is read as a local grammar repository, anything else loads
  `tree_sitter_<grammar>_jll` lazily through `Base.require`, so Dendro depends on no
  grammars itself. `query_for` reads `<queries>/<lang>.scm` and compiles it against that
  grammar. A missing grammar errors with an install hint. `scopes_query_for` and
  `imports_query_for` read the optional `.scopes.scm` and `.imports.scm` the same way,
  returning `nothing` for a language that ships none. Every cache is keyed by the whole
  profile, not the language name, so two projects registering one name against different
  grammars or queries never share a compiled query. `language_for_path` resolves an
  extension through an `extension_map` of the scan's registry, built once per scan rather
  than per file. The caches are guarded by `CACHE_LOCK`; `warm_languages` fills them for a
  profile set up front so fan-out tasks find them warm.
- `parallel.jl` defines the threading primitives the corpus fan-outs share:
  `PARALLEL_MIN` and `parallel_enabled`, `chunk_indices` (round-robin partition
  into strided ranges), `parallel_map!` (one value per item into a preallocated
  vector), `parallel_flatmap` (per-item vectors folded in index order), and
  `parallel_chunks` (a worker per chunk, each with its own state). Included after
  `resolve.jl`, whose cache functions `warm_languages` calls. See Parallelism.
- `profile.jl` defines `LanguageProfile`: a language `name` plus where to load it from,
  its `grammar`, its `queries` directory, and the `extensions` it claims. The node types
  it measures live in the language's query, not in this type. It is included before
  `resolve.jl`, which dispatches on it, and carries `QUERIES_DIR`, the built-in query
  directory (a `RelocatableFolders` path, so it survives precompilation). A built-in
  profile leaves `queries` empty and resolves that path at read time through
  `queries_dir`; baking it into the precompiled `PROFILES` would defeat the relocation.
- `profiles.jl` holds the `LanguageProfile` for each language Dendro ships. This is the
  built-in layer of the registry: `resolve_profiles` (in `config.jl`) overlays the
  languages a `.dendro.toml` registers over it, and a scan gates a file's extension on
  that resolved registry rather than on `PROFILES` directly. The built-in table is never
  mutated, so one analysis cannot leak a registration into the next.
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
  file's units. The corpus graph folds these into `within_edges`. Callee attribution
  lives here beside the coupling substrate it complements: `callees_by_unit` reads
  each unit's distinct `@callee` names in one pass (a call belongs to its innermost
  unit, a unit's own name never counts), the `fan_out` scalar is one entry's length,
  and the reimplementation fingerprints read them all. Included after `units.jl` (it
  calls `functions`), before `corpus_graph.jl` reads it.
- `metrics.jl` defines the scalar metrics and `severity`: `cyclomatic`,
  `cognitive_complexity`, `function_length`, `nesting_depth`, `parameter_count`,
  `boolean_complexity`, `return_count`, and `npath` (NPath complexity, a recursion
  that dispatches on construct family from the query and saturates at `NPATH_CAP`).
  `severity` classifies a value against a `(warn, high)` band.
- `flags.jl` defines the presence metrics: `empty_body`/`empty_bodies`,
  `empty_catches`, `stub_markers`, `returns_in_finally`, `trivial_wrappers`,
  `unreachable_statements`, `identical_operands`, `duplicate_branches`,
  `unused_parameters`, `unused_locals`, `broad_catches` (the `@broad_catch`
  concept's nodes verbatim: the query decides which handlers are broad), and
  `shadowed_variables` (a fresh
  `:local`-kind binding whose name an enclosing scope already binds; Julia's
  `:assign`-kind statement assignments rebind rather than shadow and never
  report). The scalar `local_count` lives here too, beside the unused flags whose
  binding substrate it reads. Most read the nodes one concept tagged
  and keep those a predicate accepts, through the shared `filter_nodes`. The unused
  pair reads the scopes captures instead: a `@parameter_name` or `:local`-kind
  definition inside a unit whose name no reference in that unit carries
  (`reference_positions`/`used_within`, name-based over the unit rather than
  binding-based, so a rebinding from a nested scope is not a fresh variable), with a
  leading underscore opting out. Plus the helpers: `function_body` (a block child or
  a short-form's right-hand expression), reading a body's real-work count, comparing
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
  scoring, and suppression meet. `two_scores` reads one value against its band and its
  rank among the values scored alongside it, and `fires` decides whether either half
  trips: every corpus-relational pass reads a value that way, whatever it scores.
  `scored_findings` is the whole emission the file-level passes share on top of that:
  given each file's value and the locations to report it at, it scores, reads the
  suppression directive at the first location, and returns the findings sorted.
  `min_reported` holds back a value that names nothing to act on while keeping it in the
  distribution, which is how `:split_audience` scores a single audience.
  `directory_findings` is the same emission for the two passes whose subject is a directory:
  the suppression directives arrive keyed by path rather than carried on a `ParsedFile`,
  which is the only thing that separates the two. Two renderers
  walk `Findings`: the `show`
  method for `text/plain`, and `github_annotations`, a standalone function (not a
  `show` method) that emits GitHub Actions workflow commands for inline PR
  annotations. Both share `score_suffix`. A finding renderer takes `Findings`; a
  graph renderer (`mermaid`, `mermaid.jl`) takes the corpus, since a graph is not
  recoverable from findings.
- `diff.jl` defines the unified-diff parser (`changed_ranges`, `coalesce_lines`)
  that turns a git diff into per-file line ranges, plus `inrange`/`intersects`.
- `gate.jl` defines `errors`, the gate view over `analyze`: `high_floor` keeps the
  `:high`-band findings, applied after `active`. With `since`, `base_floor_counts`
  archives the base revision and `ratchet` subtracts its floor by `fkey`, a
  line-independent location-set key. Built on plain `analyze`, it adds no branch to
  the pipeline. `git_toplevel` (`analyze.jl`) resolves the repo root for both the
  ratchet base and the spatial `base` scope.
- `clones.jl` defines both duplicate passes over a shared subtree index. `subtrees`
  hashes every named subtree of a function bottom-up. Exact: `anchor_floor` and `cluster_duplicates`
  bucket function- and block-shaped subtrees by hash, with `subsumed` as the
  maximality filter. Near-miss: `clone_features` (a unit's pre-order hash sequence,
  histogram, digest, and size from one walk), `lcs_length`/`clone_similarity` (the
  order-aware LCS verdict), `near_miss_edges!` (the size-banded characteristic-vector
  prefilter over `NearestNeighbors`, confirmed by `pair_similarity`), and
  `cluster_near_duplicates` (union-find over confirmed pairs into `:near_duplicate`
  findings). It also defines the ranking the three clone passes share: `ModulePlacement`
  resolves a corpus file to its module node and that module to its community, and
  `rank_clones!` sorts a pass's findings by `clone_distance`. Included after
  `file_graph.jl`, whose `ModuleGraph` the ranking reads, and before `analyze.jl`, which
  calls it.
- `reimplementation.jl` defines the opt-in vocabulary pass. `subtokens` splits an
  identifier into lowercase word fragments; `reimpl_units` fingerprints each
  function (callee names via `callees_by_unit` from `graph_edges.jl`, identifier
  subtokens attributed to their innermost unit, digest and size from the `clones.jl`
  subtree walk); `term_stats` builds the per-language IDF table and rare-term set;
  `reimpl_candidates` proposes pairs from an inverted index on rare terms;
  `reimpl_score` is the IDF-weighted Jaccard; `cluster_reimplementations` applies
  the gates and emits `:reimplementation` findings. Serial throughout, the scoring
  is linear in term-set size over an already-pruned candidate list. Included after
  `clones.jl`, whose `subtrees` it reuses, before `analyze.jl`, which calls it.
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
  resolution; within one language. Included before `analyze.jl`, which calls it.
- `linkage.jl` is the registry side of cross-file resolution: how each language lets one
  file see another's names, and the readings of a language's linkage query those rules are
  written over. `Linkage`/`LINKAGES` carry the model per language, `:splice`, `:import`,
  `:directory`, or `:package`, with `resolve_target` mapping a declared target to corpus
  paths (`splice_resolve` for a Julia `include`, `js_resolve` for an ECMAScript specifier,
  which also tries a `.js` specifier's TypeScript source, and so on). `Linkage.is_public`
  and the per-language predicates (`export_public`, `underscore_public`,
  `capitalized_public`, `modifier_public`) decide public-API membership; the convention
  predicates read a `CorpusDef`'s name, `modifier_public` reads its `visibility`, set by
  `def_visibility` from a grammar-specific modifier (Rust `pub`, a C/C++ `static` function,
  a Ruby/Java/PHP `private` method, a package-private Java class). It also holds what each
  model makes visible for one file, `file_visible` over `member_visible`, `import_visible`,
  `package_visible` and `merge_visible`, where the `:package` model (Java) unions import
  visibility with the same-directory types a package resolves without an import, so a
  package-private class reference resolves. The query readings live here too: `file_exports`,
  `file_imports`, `include_targets`, `declared_targets`, and `module_regions`, along with
  `file_symbols!`, what one language declares as a top-level symbol. `CorpusDef` and
  `SymbolTable` are defined here rather than beside the pass that builds them, because every
  per-language predicate is written over one. `Corpus` and the POSIX path helpers back the
  resolvers. One independent rule per language with nothing to connect them, so the file
  carries `dendro-ignore-file: low_cohesion` by design. Included after `naturalness.jl`.
- `resolution.jl` resolves the corpus against that registry, the layer every pass past a
  single file reads. `corpus_symbols` fans `file_symbols!` over the corpus into one
  `SymbolTable`; `unbound_references` collects the references the per-file resolver left
  unbound, and `CorpusReference` pairs one with the candidates its name reaches.
  `splice_graph` groups files into shared namespaces by an inclusion union-find,
  `DeclaredLinkage` holds it beside each file's export set so one walk serves both readings,
  `visible_defs` returns each file's cross-file candidates over a shared `VisibilityIndex`,
  and `corpus_references` yields every resolved cross-file reference. Two summaries sit on
  top: `consumer_sets`, per definition, who references each consumed one, read by
  `:split_audience` and `:hub`, and `public_surface`, per file, the export gate, the file's
  own for an import model and the inclusion component's for a splice. `ResolvedLinkage` and
  `resolve_linkage` bundle the visibility, the references, the consumers and the surface into
  the one value a scan resolves once and every pass takes. Reuses the `bindings.jl` capture
  walk and the `clones.jl` union-find. Included after `linkage.jl`.
- `corpus_graph.jl` defines the corpus unit graph, the one structure the three placement
  passes read. `build_corpus_graph` resolves every unbound reference against the symbol
  table through `visible_defs`, recording weighted unit-to-unit `edges` and per-unit file
  mass; a reference matching `k` definitions splits `1/k`, and a definition referenced by
  more than `CORPUS_UBIQUITY` of the units that can see it (`ubiquity_threshold` over
  `definition_reach`) is dropped as cross-cutting. It also folds each
  file's within-file binding edges (`within_binding_edges` over `binding_groups`) into
  `within_edges`. `adjacency(graph; within)` builds the undirected neighbour-weight view,
  cross-file alone or with the within edges folded in; `communities` runs one level of
  modularity optimisation (`local_moving!`, Louvain) for the neighbourhoods, once per
  connected component against that component's own degree sum, and
  `components` flood-fills the within view restricted to one file's nodes for cohesion.
  Both denominators are local by design: a unit's placement verdict follows from the code
  that can couple to it, never from how much unrelated source shares the corpus.
  `definition_reach` lives here rather than with the rest of the resolution, since the
  ubiquity cut is its only reader. Included after `resolution.jl`.
- `file_graph.jl` defines the corpus file graph, the same resolution read one level up.
  `build_file_graph` walks `corpus_references` and records a weighted `FileEdge` per
  ordered file pair, carrying the definition names behind it (`top_names`, capped at
  `EDGE_NAMES_MAX` and paired with the true count) and the import statements admitting it
  (`declared_edges` over `linkage.jl`'s `resolved_targets`, which maps each declared target
  to corpus paths through the language's `Linkage` resolver; the walk fans out per file and
  only the fold into the shared edge map is serial). It drops no cross-cutting definition and
  skips self-edges, and `edge_weight` floors a split reference at one so rounding never
  erases an edge. `module_graph` contracts by a grouping function, summing weights and
  dropping within-group edges; `build_file_graph` runs it by `dirname` and keeps the result
  as the graph's `modules`, and `module_communities` runs `corpus_graph.jl`'s modularity
  optimisation over the undirected reading of that contraction. It reads a
  prebuilt `ResolvedLinkage` from `resolve_linkage`, the same value `build_corpus_graph`
  accepts, and returns its nodes without walking anything when the corpus holds one file,
  since an edge joins two. Included after `corpus_graph.jl`, before `clones.jl` ranks
  against it.
- `back_edge.jl` defines the first rule over the file graph. `dominated_pairs` reads the
  directory-contracted graph for each pair coupled both ways whose majority direction
  clears `BACK_EDGE_MIN_MAJOR`, scoring the dominance percent; `minority_edges` names the
  file edges running the minority way, and `edge_reference_sites` resolves the references
  behind them back to `Location`s. `cluster_back_edge` emits a `:back_edge` finding per
  minority file edge, carrying the absolute `BACK_EDGE_BAND` and the percentile over the
  bidirectional pairs. Included after `file_graph.jl`, before `analyze.jl` calls it.
- `dependency_cycle.jl` defines the cycle rule over the same graph. `successors` reads the
  graph's sorted edge keys into adjacency lists, `strong_components` runs Tarjan over them
  (`TarjanState` carries the recursion's index, low-link, and stack), and per component
  `induced_subgraph` and `feedback_arcs` run the Eades-Lin-Smyth heuristic
  (`linear_arrangement` over `next_vertex`/`max_delta`) weighted by reference count, so the
  edges left pointing backwards are the light ones. `cluster_dependency_cycles` emits a
  `:dependency_cycle` finding per component of two or more files, scored on the component
  size against `DEPENDENCY_CYCLE_BAND` and the corpus percentile. Its locations are the cuts
  (`cut_location`) when the feedback set fits `CYCLE_LOCATIONS_MAX`, else the tangle's
  highest-degree members (`tangle_locations`). Included after `back_edge.jl`.
- `placement.jl` defines cross-file placement, the fourth corpus-relational pass.
  `own_affinity` reads each unit's same-file coupling from `index.bindings`;
  `community_plurality` finds the group each community is anchored in, the unit's file by
  default and whatever its `key` names otherwise; `cluster_misplaced`
  emits a `:misplaced` finding per envious unit, scored by the share of its whole
  coupling landing in the one other file it leans toward most, carrying the absolute
  `MISPLACED_BAND` and the corpus percentile, gated by the community anchor. Included
  before `analyze.jl`, which calls it.
- `scattered.jl` defines cross-file scattering, the file-level companion to
  `:low_cohesion`. `cluster_scattered` reads `communities(adjacency(graph; within = true))`,
  the corpus graph with each file's within-file binding edges folded in, so `communities`
  sees a file's own cohesion and a file's units land in communities. It emits a
  `:scattered` finding per file, scored by the count of distinct communities its units
  occupy whose plurality anchor is another file, carrying the absolute `SCATTERED_BAND`
  and the corpus percentile. Included after `placement.jl`.
- `incoherent_package.jl` reads the same communities per directory, the opt-in pass
  `analyze` gates on `cfg.rules`. `community_plurality` keyed by `dirname` anchors each
  community in a directory, `community_anchor` picks the unit representing it there, and
  `cluster_incoherent_packages` emits an `:incoherent_package` finding per directory,
  scored by the percentage of its units whose community is anchored elsewhere against
  `INCOHERENT_PACKAGE_BAND` and the corpus percentile. It reads the filtered graph, as
  placement does, since community detection needs the cross-cutting cut. Its locations pair
  a representative unit of the directory with the unit anchoring that unit's community,
  which is how the finding names a directory without inventing a path. Included after
  `scattered.jl`.
- `divisible_package.jl` asks the inward layout question, the other opt-in pass `analyze`
  gates on `cfg.rules`. Where `:incoherent_package` asks whether a directory's contents
  belong elsewhere, this asks whether they want subdividing where they are. `child_graph`
  induces the file graph on one directory's direct children, contracting a child directory
  into one node with everything under it folded in, which is what lets the same reading
  cover a directory of files dividing into folders and a directory of subdirectories
  grouping under new parents. `movable_children` drops the children a proposal cannot move,
  those most of the directory reaches for and those naming the directory itself, the
  per-directory analog of the corpus ubiquity cut. `folder_candidates` scores each community
  of the remainder by its internal ratio, `read_divisible` applies the gates that decide
  whether the question applies at all, and `cluster_divisible_packages` emits a
  `:divisible_package` finding per directory against `DIVISIBLE_PACKAGE_BAND` and the corpus
  percentile. Groups are extracted rather than partitioned: what no folder claims stays at
  the top level, and the anchor location's label says how much the proposal places. Included
  after `incoherent_package.jl`.
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
- `hub.jl` defines the Crossing pass over the file graph, the one relational metric read at
  file-graph level. `crossing_scores` counts each file's distinct dependents and
  dependencies and scores `min(fan_in, fan_out)`, the conjunction that separates a crossing
  from a utility or an orchestrator; `cluster_hub` emits a `:hub` finding per file, carrying
  the absolute `HUB_BAND` and the percentile over the files that cross at all, skipping a
  corpus below `MIN_HUB_CORPUS_FILES`. The proposal is the split, read through
  `resolution.jl`'s `consumer_sets` and `split_audience.jl`'s `audience_components` with the
  hub's own per-group consumer floor, `audience_reps` taking one representative per group as
  the extra locations on the finding. The consumer index comes off the shared
  `ResolvedLinkage`, which `:split_audience` reads over every file anyway.
  Included after `split_audience.jl`, whose grouping it calls, before `analyze.jl`, which
  calls it.
- `split_audience.jl` defines the outward dual of cohesion, the corpus-relational pass
  that reads the resolved references without either graph, and the audience machinery
  `:hub` shares. `consumer_sets` collects, per definition referenced from outside its
  file, the files that reference it; `audience_components` links two definitions whose
  consumer sets meet (star-linking each consumer's definitions, so the components match
  pairwise linking at linear cost) and reads the components through `components`, the
  same flood fill cohesion uses, returning the qualifying groups earliest line first;
  `cluster_split_audience` emits a `:split_audience` finding per file through
  `scored_findings`, scored by the count of groups holding at least `MIN_AUDIENCE_DEFS`
  definitions, carrying the absolute `SPLIT_AUDIENCE_BAND` and the corpus percentile,
  with one representative definition per group as its locations. A file below
  `MIN_SPLIT_GROUPS` audiences names no split and is never reported, but stays in the
  scored population the percentile reads. Resolved consumers rather than declared
  exports, since a language with no export marker exposes every top-level name. The
  consumer floor is on the file's whole audience here and on each group in `:hub`, which
  names the groups rather than counting them. Included after `cohesion.jl`, before
  `config.jl`, whose band cascade names its band.
- `ignore.jl` defines the path filter behind `analyze`'s `ignore` keyword:
  `glob_to_regex` translates one gitignore pattern, `compile_ignores` builds the
  pattern list, `is_ignored` decides a path (last match wins, negation re-includes).
  Pure path logic, no parsing. Included before `corpus.jl`, which calls it.
- `config.jl` defines the immutable `Config` and the threshold cascade:
  `discover_config` (accumulate the user-global then repo `.dendro.toml` overrides and
  build one `Config`), `apply_toml!` (one layer, warning on unknown keys), and
  `resolve_rules` (the config's rule set). Included before `analyze.jl`, which calls it.
- `corpus.jl` gathers the corpus and nothing more: `source_files` (recurse a folder for
  analysable files, pruning ignored paths), `collect_corpus` (resolve a list of roots to
  the unique set of file paths to parse, the shared front of `analyze` and `mermaid`),
  `parse_corpus` (parse each path once and build its query index into a
  `Vector{ParsedFile}`), and `parse_chunk!` (one chunk of that fan-out, with its own
  parser pool). Parsing is the one boundary that turns a file away: tree-sitter takes the
  source as a C string, so a file carrying an embedded NUL cannot be parsed at all.
  `parse_chunk!` warns with the path and leaves the slot unassigned, and `parse_corpus`
  compacts in index order, so one such file, a fuzzer test case checked in beside real
  source, is reported rather than taking the scan down. Gathering and driving are separate
  files because one file holding both
  has its units pulled toward every pass it calls as well as the parsing primitives,
  which is what `:scattered` measures; splitting on that seam is the fix the rule asks
  for rather than a band retune.
- `analyze.jl` drives the passes over those records: `analyze` (the public entrypoint,
  orchestrating corpus, baseline, per-file findings, then the clone and relational
  passes), `resolve_corpus` (the `CorpusResolution` the passes past a single file share,
  the symbol table, the `ResolvedLinkage` over it, and both graphs, built once),
  `clone_clusters`
  (exact and near duplicates plus the config-gated reimplementation pass, each ranked
  against the `ModulePlacement`), `relational_clusters` (naturalness, low cohesion,
  cross-file placement, scattering, unreferenced definitions, the audience pass over the
  symbol table, the two config-gated directory passes, and the three passes over the
  file graph, in the order a report reads them), and the diff scope, `Scope` and
  `scope_clusters`, which live here because they are `analyze`'s framing of the question
  rather than a property of the corpus. It is included after `corpus.jl` and after
  `report.jl`, `diff.jl`, `naturalness.jl`, `linkage.jl`, `corpus_graph.jl`,
  `file_graph.jl`, `clones.jl`, `reimplementation.jl`, `placement.jl`, `scattered.jl`,
  `incoherent_package.jl`, `divisible_package.jl`, `cohesion.jl`, `hub.jl`, and
  `split_audience.jl` so everything
  it calls is defined first.
- `mermaid.jl` defines `mermaid`, the graph renderers that turn the corpus coupling
  graph, the dead-code reachability graph, and the clone clusters into mermaid
  `flowchart` text, with `:file` and `:unit` granularity and active findings overlaid.
  `focus` trims a view to the flagged nodes grown `context` hops over the graph, so the
  unit views stay legible and renderable; `neighbourhood` does the growth, generic over
  the unit-index and file-path node ids. A graph renderer rebuilds the structure it draws
  from the corpus rather than from `Findings`. Included after `corpus.jl`, whose
  `collect_corpus` and `parse_corpus` it reuses.
- `main.jl` defines the CLI `main` behind `julia -m Dendro` and the `dendro` app:
  `parse_args` into `CLIOptions`, `run_cli` (discover config, `analyze`, emit, exit
  code), and the `@main` wiring. Included last, since it calls `analyze`, `active`,
  and `github_annotations`.

## Core types

`LanguageProfile` (`profile.jl`). Just a language `name`. The set of profiles is
what `analyze` gates a file's extension on; the node types each language uses live
in its query, not here.

`QueryIndex` (`query_index.jl`). One tree's identified nodes: the `functions` units
and `function_ids` (the no-descend boundary), plus one `Concept` per measured
construct (decision points, short-circuit operators, nesting, parameters, parameter
names, bodies,
catches, broad catches, comments, names, trivial statements, returns, finally clauses, calls,
callee names,
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

`CorpusReference` (`resolution.jl`). One resolved cross-file reference: the file it sits
in, the `UnboundRef` itself, and the `SymbolTable.defs` indices its name reaches. A name
matching several visible definitions carries all of them, since picking one would need
dispatch resolution. A concrete record rather than the three-tuple it replaced, so the
five passes that walk the references read fields instead of positions.

`DeclaredLinkage` (`resolution.jl`). What the corpus declares about linkage, walked once:
each file's export names and the splice graph joining files into one namespace.
`visible_defs` and `public_surface` are both readings of it, which is what stopped the
scan walking the export and include captures twice.

`ResolvedLinkage` (`resolution.jl`). The corpus resolved against itself, and the value a
pass takes instead of resolving again: each file's cross-file candidates by name, the
references those candidates admit, who consumes each definition, and each file's public
surface. `resolve_linkage` builds one per scan. It occupies the keyword slot the bare
visibility map used to, so widening what is shared cost no pass a parameter, which matters
because `parameter_count` at its `:high` band would put a rule into Dendro's own error
floor.

`ModulePlacement` (`clones.jl`). Where each corpus file sits in the module graph: the
file-to-module-node map and the community label per module node. `analyze` resolves one and
hands it to every clone pass, so a corpus with three of them pays for one community
optimisation. `clone_distance` is the only reader.

`Scope` (`analyze.jl`). The diff-scoped view's data: the git toplevel `root`, the changed
line ranges per file relative to it (`Dict{String, Vector{UnitRange{Int}}}`), and `rels`,
every corpus file's path already resolved against that root. `analyze` builds one from
`base`'s diff, and `scope_clusters` filters cluster findings to it through `in_scope`.
Several scanned roots still resolve to one toplevel and one repo-wide diff, since findings
carry absolute paths that `relpath` against `root` regardless of root. A concrete record, so
the diff-scoping passes dispatch statically rather than over an ad-hoc NamedTuple.

`rels` is resolved once over the corpus rather than per location. `realpath` is a syscall,
a dozen passes scope their findings against one `Scope`, and the architecture rules carry
many locations apiece, so resolving per location would repeat the same file's syscall
through a whole run. Building it before the per-file scan is also what keeps it read-only,
so the parallel pass shares it with no lock. The gate's `fkey` memoizes the same resolution
per keying pass, through `relative_to` (`gate.jl`), where the corpus is not to hand.

`Location` (`report.jl`). A code site: file, 1-based line, enclosing unit name, and an
optional label. A `Finding` carries one or more. A finding about something larger than a unit
points at a representative real site rather than inventing one: `:scattered` names one
unit per community, and `:incoherent_package`, whose subject is a directory, names a
representative unit in it. `:divisible_package` does the same for a directory and for each
folder it proposes, naming the earliest file the group holds, so a proposed folder made of
subdirectories still points at code. Both `scope_clusters` and the gate's `fkey` resolve a
location's path and line, so a synthetic path or line would throw in the ratchet and
misbehave under `base`.

The label is what turns a score into an edit. A pass that computes the other end of a
relation and reports only its own side leaves the reader to rebuild the graph: `:scattered`
labels each unit with the file its community is anchored in, and `:split_audience` and
`:hub` label each representative with the files consuming its audience (`label_path` in
`placement.jl` renders the path, `audience_location` in `split_audience.jl` the consumer
list, capped at `AUDIENCE_CONSUMERS_MAX` with a count for the rest). A label is evidence,
not identity, so `fkey` reads file and unit alone and labelling a site never moves a ratchet
key. Where the label *is* the identity, `:dependency_cycle`'s choice of which edge to cut,
it goes in the unit field instead and does enter the key. `:misplaced` needs no label: its
second location is a real site in the target file.

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
function- and block-shaped subtrees anchor a finding: `anchor_floor` admits a block
at twice `min_size` named nodes and defers a function to `unit_floor`, which admits a
function with control flow at `min_size` and a control-free one at twice that. A short
block of boilerplate coincides across unrelated code. So does a control-free whole
function, a dispatch stub or forwarding overload. A function with control flow is
already a meaningful unit at the lower floor. `has_control` is the predicate: a branch
point or a nesting construct anywhere in the subtree. Expressions and lone statements
never anchor. A bucket of
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
   characteristic vector (for the prefilter), its exact digest, and its size. A unit
   joins the index only if its size clears `unit_floor`, so a trivial function is held
   to twice `min_size` here as it is in the exact pass.
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

All three clone passes are then ranked against the module graph. `ModulePlacement` holds
the file-to-module map and `module_communities`' label per module; `clone_distance` reads a
cluster as `0` inside one file, `1` inside one directory, `2` inside one community of
directories, `3` across communities. The levels nest, so the widest gap between two members
is the cluster's level. `rank_clones!` sorts by it, widest first, stably, so each pass's own
key (cluster size then location for the structural passes, overlap score for
`:reimplementation`) still decides ties inside one distance. What the scale reads is how
much of the system a duplicate implicates: two copies in one file are an edit one reader
makes in one sitting, two copies either side of a community boundary are a missing
abstraction that parts of the system built twice.

Ranking is all it is. `value`, `absolute`, and every finding's locations come through
untouched, so the result is a permutation of the pass output. That is not incidental:
`:duplicate` is emitted at the `:high` band and therefore sits inside the floor `errors`
returns, and the ratchet keys a finding by `(metric, sorted location set)`. A re-rank that
touched a band would move that floor under every package gating on Dendro, so the invariant
is asserted rather than assumed, against the pass output on a fixture corpus and against
Dendro's own source.

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

## The file graph

`build_corpus_graph` answers where a unit belongs. `build_file_graph` (`file_graph.jl`)
answers which file depends on which. Nodes are every corpus file, sorted, and a directed
edge records that one file's code references definitions in another.

Both read the `corpus_references` of one shared `ResolvedLinkage`, and both split a
reference matching `k` visible definitions `1/k` across them. What differs is the filter and
the level. The unit graph drops a reference to a definition more than `CORPUS_UBIQUITY` of
the units that can see it reach, so a shared helper does not pull a unit toward its file;
the file graph keeps every resolved reference, since a file every other file reaches for is
the observation an architecture question is after. A reference in top-level code counts here
where the unit graph skips it: the file depends on the target whether or not a function
encloses the reference. Self-edges are dropped, since a file's coupling to itself is what
`:low_cohesion` reads and here it would only swamp every node's degree.

The edge carries its own evidence. "File A depends on file B" is not something to edit, so a
`FileEdge` holds the distinct definition names crossing it, the heaviest `EDGE_NAMES_MAX` of
them with the true count beside them, and the `Location` of every import or include
statement admitting it, resolved through the language's `Linkage`. A statement attaches to
an edge references already built; an import nothing uses draws no edge. `first_line` gives
every file a real line so a file-level finding never invents one, and every corpus file is a
node, one with no units and one with no edges included: an isolated file is an observation,
and dropping it would move the denominator of every corpus-relative score.

Weights accumulate as `Float64` and round once, when the edge is finalised, so a reference
split three ways does not round away on the way in. `edge_weight` floors the result at one:
an edge exists because a reference built it, and reporting that as weight zero would deny a
dependency the code has.

`edges` is a `Dict`, so its iteration order is not the corpus order. Every consumer sorts its
working set before reading it, the discipline `cluster_scattered` and `cluster_low_cohesion`
already follow, which is what keeps output byte-identical at any thread count.

`module_graph` contracts the graph by a grouping function, for the rules that read
directories rather than files. `build_file_graph` runs it by `dirname` and keeps the result
as the graph's `modules` field: no query work, available in every language, and what a repo
usually means by a module. A declared-module grouping is available in some languages and not
others, which would make one rule fire differently across a polyglot corpus for reasons
unrelated to the code. Weights sum across the file edges between two groups; an edge inside
one group is dropped.

The contraction is a field because its readers have to agree. The clone ranking measures a
cluster's spread across these groups and `:back_edge` reads the grain between them, and two
rules disagreeing about what a module is would be a bug no test would name. It also takes
the graph's pieces rather than the graph, since it runs while `build_file_graph` is still
assembling the `FileGraph` that will hold it.

## Dependencies against the grain

`cluster_back_edge` (`back_edge.jl`) is the first rule over the file graph. Contract by
directory and read the traffic between two directories both ways: when one direction carries
almost all of it, the code has settled on a layering, and each reference going the other way
runs against it. The grain comes from the corpus, so no declared layer order and no
configuration is involved. A pair whose majority direction carries fewer than
`BACK_EDGE_MIN_MAJOR` references has settled on no direction and is not scored, and a corpus
whose files sit in one directory contracts to one group and yields no pairs at all.

Dominance is a ratio, so a high score says the direction is one-way and never that the way
back is short. A pair with a large majority side clears the band while carrying dozens of
minority references, one finding each: CommonMark.jl's root against `writers` scores 95 on
15 references over 14 file edges. The location count is what bounds the edit.

`BACK_EDGE_EDGE_CAP` is what keeps that difference out of the gate. A pair spreading its
minority direction over more file edges than the cap reports below `:high` whatever its
dominance, so one architectural observation cannot become a dozen gate errors when no
single edit resolves it. The findings still name every minority edge; they stop claiming
an edit the pair cannot deliver. Same reasoning as a cycle component too tangled to cut,
reported as a tangle rather than as a feedback set. Of the seventeen pairs reaching the
high threshold across the calibration corpora, sixteen spread over one to four edges and
the seventeenth over fourteen, so the cap sits in a measured gap.

Higher dominance is worse, the direction the band model expects: a pair at 60/40 is a
genuinely mutual dependency, which is a cycle rather than a violated grain. Scored like the
other relational metrics, the absolute `BACK_EDGE_BAND` on the dominance percent and the
percentile over the bidirectional pairs, fired when either trips. One finding per file edge
in the minority direction, not one per pair: the edit is to an edge.

The locations are wider than any per-file metric's, and deliberately. They run the minority
edge's import statement first, then every reference site across the edge, because a diff that
adds a use of an already-imported name introduces a back edge without touching the import's
line, and locating the finding at the import alone would drop it under `analyze`'s `base`
scoping. The cost lands in the gate: `fkey` is the location set, so an edge's key grows as
references accumulate across it, and adding one to an established back edge re-reports a
violation the base already carried. That is the reading the rule wants rather than a defect,
since the ratchet exists to catch worsening. `back_edge.jl` documents it and `test/back_edge.jl`
pins it, so a later change that "fixes" the re-report argues with a failing test.

The cap runs the other way. A diff adding a back-referencing file, taking a pair from
`BACK_EDGE_EDGE_CAP` edges to one more, demotes every finding on that pair to `:warn` at
once, so violations that gated in the base leave `errors` and the ratchet sees them go:
widening the coupling can empty the gate for that pair rather than fill it. That follows
from the cap being right, since none of those findings names a bounded edit any more, but
it does mean this rule's gate contribution is not monotone in how bad the coupling is. The
finding count is, and does not drop.

## Dependency cycles

`cluster_dependency_cycles` (`dependency_cycle.jl`) reads the same graph for cycles, and the
shape of the finding is the whole design. Cycle membership describes most of a real
codebase: measured over nine corpora it covered 319 of 4528 files overall, and 84% of the
files in the worst of them. A rule firing that broadly names no edit and takes the `errors`
floor with it. So the finding is the **feedback arc set**, the edges whose removal would
make the component acyclic. The same nine corpora put seven findings in the floor.

Tarjan finds the components, over adjacency lists built from the graph's sorted edge keys.
Each component of two or more files goes to the Eades-Lin-Smyth heuristic, weighted by
reference count: peel sinks to the right of a linear arrangement and sources to the left,
and absent either take the vertex whose weighted out-degree most exceeds its in-degree. That
sends the heavy dependencies forward, so what points backwards afterwards is the light
traffic, which is the cheaper edit. Eades-Lin-Smyth bounds the size of the set it returns
and runs in linear time; it does not return a minimum feedback arc set, and nothing in the
report claims it does.

The score is the component size, against `DEPENDENCY_CYCLE_BAND` and the corpus percentile
over every cyclic component's size, with `MIN_CYCLE_COMPONENTS` withholding the percentile
on a corpus too thin to rank against. The percentile half fired on none of the nine
calibration corpora, since a corpus large enough to rank against carries enough small cycles
that they tie low; the band carries this metric in practice. Locations are where the two
kinds of finding part.
Under `CYCLE_LOCATIONS_MAX` cuts, each location is one edge to remove, at the import
statement admitting it where the language declares one, labelled `cut -> <target>`, the
target named relative to the source file's directory. That label is part of the finding's
ratchet key (`fkey`, `gate.jl`), which is scored once in place and once in a `git archive`
tempdir, so an absolute target would re-report every cut finding as new. Above
it, the component has no bounded edit: the locations become its highest-degree members and
every label reads `tangled: <n> cuts`. Reporting the tangle rather than dropping it is the
honest-over-silent call, and the label is what tells the two apart without inferring
anything from the location count.

## Hub files

`cluster_hub` (`hub.jl`) reads the same graph per file, for the Crossing anti-pattern:
a file both depended on by much of the corpus and depending on much of it propagates every
change in either direction. The score is `min(fan_in, fan_out)` over distinct file counts,
and the `min` is the whole rule. Fan-in alone is every utility module and fan-out alone
every orchestrator; only the conjunction names the file in the middle. A file with no edge
in one direction is not a crossing, so it neither fires nor enters the population the
percentile ranks against.

Both scores fire it, and here the rank does most of the work: fan-in and fan-out grow with
the corpus, so `HUB_BAND` can only mark the level at which a crossing reads as central
whatever the corpus. `MIN_HUB_CORPUS_FILES` silences the rule below a corpus where every
file touches most of the others, and unlike `MIN_COHESION_FILES` it gates the rule rather
than only its percentile, since the absolute reading is as size-dependent as the rank.

The finding proposes the split. `consumer_sets` collects, for each definition in a firing
file, which files reference it; two definitions belong to the same audience when a consumer
reaches both, and `audience_reps` reads those groups off the same `components` flood fill
cohesion uses, returning one representative definition each. A group under
`MIN_AUDIENCE_DEFS` or `MIN_AUDIENCE_CONSUMERS` is not an audience: one definition one file
uses is ordinary, and a proposal built from singletons would name every definition its own
audience. The first location is the file at its first unit and the surviving
representatives follow, so the extra locations are the proposed edit. A hub left with fewer
than two audiences carries the file alone: a warning with no proposal states its case
better than a split that does not hold. The consumer index comes off the corpus resolution
the scan already shares, so the proposal costs this rule the grouping of a firing file's
definitions and nothing more.

That puts consumer structure in the location set, which the ratchet keys on. A change that
merges or splits a hub's audiences rewrites `fkey` and the gate reports the finding as new,
the trade `:back_edge` makes for the same reason: the proposal the earlier finding carried
no longer holds, so re-reporting is the behaviour, not a defect in the key.

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
- A scalar's corpus percentile is read only where the distribution supports a rank.
  `percentile_informs` asks what rank a single occurrence gets: when that already breaches
  the cut, every unit in the corpus sits above it and the rule reports each function for
  containing nothing. Resolved once per `(language, metric)` per scan and carried on the
  `Scan`. The absolute band is untouched, so this decides whether the rank is read and
  never what the fixed band says. Measured across eight corpora: `cyclomatic` and
  `function_length` do not move, `cognitive_complexity` moves by four findings in 450, and
  `boolean_complexity` falls 97.8%, having reported every unit in one corpus.
- There are two query families and they never merge. `<lang>.scm` captures name
  concepts: the set is closed (`CONCEPT_NAMES`), `dispatch!` throws on anything outside
  it, and the suite guards every query against it. That closure is what keeps metric code
  free of grammar node types. A user's `<lang>.patterns.scm` capture names a *rule*: the
  set is open and the queries are written against concrete node types on purpose, since
  being language-specific is the point of the family. They are separate `TreeSitter.Query`
  objects from separate files, walked in separate passes, bucketed into
  `QueryIndex.patterns` rather than routed through `dispatch!`. Merging them takes
  `dispatch!`'s closure with it and metric code starts special-casing languages.
- A pattern rule resolves to an ordinary `Rule`, which is what makes suppression, diff
  scoping, the report, the gate, and the ratchet work for it with no further code.
  Negation is a `.not` capture subtracting by node identity; a `_`-prefixed capture is a
  predicate helper and never a rule; a capture naming no declared rule is a load error.
- Adding a language is data only: a query in `src/queries/<lang>.scm`, a
  `LanguageProfile` entry in `profiles.jl`, and an extension entry in `resolve.jl`.
  No metric code changes. If a metric needs a language special case, the query is
  missing a capture; add the pattern. A `src/queries/<lang>.scopes.scm` is optional;
  with it the language gains binding resolution and cohesion, without it both skip.
- A project adds a language without touching the package through `[languages.<name>]`
  in its `.dendro.toml`, naming a queries directory and optionally a grammar directory
  and extensions. Same three pieces of data, supplied from outside. Such a language
  reaches the per-file passes and clone detection; the cross-file passes need a
  `LINKAGES` entry, which is Julia code in the package, so they skip it. The resolved
  profile travels on each `ParsedFile`, which is what lets the corpus passes reach a
  registered language's scopes and linkage queries: they hold a file and no registry,
  and a config-registered language cannot be looked up by name alone.
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

`test/dogfood.jl` runs Dendro on its own `src/` and asserts `isempty(errors(src))`:
the `:high`-band floor must be clean. This is the all-`:high` superset, a wider gate
than the metric list it replaced, so it auto-adopts any future high-band metric. The
floor is percentile-free, so the result does not depend on the corpus distribution. A
change that makes Dendro trip its own metrics is a signal to fix the code. The two
`parameter_count` sites the floor surfaces (the `Finding` constructor, `mermaid_coupling`)
carry inline `dendro-ignore: parameter_count` with a reason, suppressed rather than
omitted from the gate, so the count stays honest.

`test/jet.jl` is the `:jet` item: basic-mode JET is a zero-tolerance gate on every
Julia version, sound mode and the optimization analyzer are ratcheted at
`SOUND_LIMIT`/`OPT_LIMIT` (pinned to one Julia version, lowered when a count drops).
