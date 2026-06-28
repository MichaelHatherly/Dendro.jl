# TODO

Deferred items from the corpus-binding-graph work (branch `mh/corpus-binding-graph`).
Each is self-contained. Read the orientation and test-loop sections first; they are the
non-obvious parts of working in this repo.

## Orientation: what the branch added

The feature is corpus-wide cross-file name resolution and a placement metric. New source
files, in `include` order in `src/Dendro.jl` (after `cohesion.jl`):

- `src/linkage.jl` — the corpus symbol table (`corpus_symbols` -> `SymbolTable` of every
  top-level definition keyed by `(language, module_path, name)`), `unbound_references`,
  and the per-language linkage registry. `Linkage`/`LINKAGES` map each language to one of
  three models: `:splice` (Julia `include`, C/C++ `#include`, Ruby `require_relative`),
  `:import` (Python, JS, TS, Rust, Java, PHP), `:directory` (Go). `visible_defs` returns,
  per file, the cross-file definitions it can reference. This file carries a
  `dendro-ignore-file: low_cohesion` because it is a registry of independent per-language
  resolvers with nothing to connect.
- `src/corpus_graph.jl` — `build_corpus_graph` resolves unbound references into a weighted
  unit graph (`CorpusGraph`); `communities` runs one level of Louvain local-moving over the
  undirected graph. `CORPUS_UBIQUITY` drops cross-cutting definitions (a helper many units
  reach for), the corpus analog of `COHESION_UBIQUITY`.
- `src/placement.jl` — `cluster_misplaced` emits `:misplaced`. Score is the share of a
  unit's whole coupling (own-file plus cross-file) landing in the single other file it
  leans toward most; `own_affinity` reads same-file coupling from `index.bindings`. The
  community anchor (`community_plurality`) gates candidacy.
- `src/scattered.jl` — `cluster_scattered` emits `:scattered`, the file-level companion to
  `:low_cohesion`. `combined_adjacency` folds each file's within-file binding edges
  (`binding_groups`, shared with `cohesion.jl`) into the corpus graph before `communities`
  runs, so a cohesive file's units cluster; the score counts the communities a file's units
  occupy that are anchored elsewhere.

Per-language linkage queries live in `src/queries/<lang>.imports.scm` (Go ships none; it
groups by directory). The capture vocabulary is `@module`/`@module.name`,
`@import`/`@import.from`/`@import.name`, `@export`, `@include.path`, guarded by the
"every imports query uses only known capture names" item in `test/query_index.jl`.

Docs describing the redrawn boundary (lexical name resolution across files is in scope;
types and dispatch are not): `AGENTS.md`, `README.md` ("Cross-file placement" section),
`ARCHITECTURE.md` (the `linkage.jl`/`corpus_graph.jl`/`placement.jl`/`scattered.jl` layer
entries).

## Test loop (read before running anything)

The suite is TestItemRunner. Quirks that will waste time if unknown:

- Language parsers are dev-deps of the test environment, not the package, so parsing only
  works under the test env. The package's own startup loads Revise, which is broken in the
  sandbox Julia; always pass `--startup-file=no`.
- To run the whole suite: `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`.
  Redirect to a file and read on failure; do not pipe through head/tail/grep during the run.
- To run one tag fast, use TestEnv and call `run_tests` with the package-root path (the
  `@run_package_tests` macro misresolves the scan root from a scratch script and walks into
  system directories). This script works:

  ```julia
  # /tmp/run_tag.jl
  using TestEnv; TestEnv.activate()
  using TestItemRunner
  tag = Symbol(ARGS[1])
  TestItemRunner.run_tests("/Users/mike/personal/Dendro.jl"; filter = ti -> (tag in ti.tags))
  ```

  `julia --startup-file=no --project=. /tmp/run_tag.jl placement`. Tags in play:
  `linkage`, `corpus_graph`, `placement`, `dogfood`, `query_index`, `jet`.
- Format with `just fmt`; check with `just fmt-check` (Runic, `.jl` only).
- `test/dogfood.jl` runs Dendro on its own `src/` and must stay clean. If a change makes
  Dendro flag its own code, fix the code (or `dendro-ignore` a legitimate case), never the
  test. This already bit twice during the feature: the two thin query-loaders in
  `resolve.jl` (`dendro-ignore: duplicate`) and `linkage.jl`'s registry cohesion.

## Re-enable the JET gate

`test/jet.jl` is disabled: the real `@testitem "JET"` is commented out (`#= ... =#`) and
replaced by a `@test true skip = true` stub. The original ran `JET.test_package(Dendro;
mode = :basic)` as a zero-tolerance gate plus ratcheted sound/opt limits
(`SOUND_LIMIT = 467`, `OPT_LIMIT = 7`, pinned to Julia 1.12). Restore that block verbatim
once green.

### Symptom

`JET.report_package(Dendro; target_defined_modules = true, mode = :basic)` throws, it does
not return reports:

```
CRASH: Expected MethodTableView
  error(s::String) at error.jl:44
  invoke_mt_compiler(::Core.MethodTable, ::Symbol, ::Type, ::Vararg{Any}) at reflection.jl:279
  _which(tt::Type; method_table::Core.MethodTable, world::UInt64, raise::Bool) at reflection.jl:888
  analyze_from_definitions!(analyzer::JET.JETAnalyzer{JET.BasicPass}, ...) at virtualprocess.jl:614
  virtual_process(...) at virtualprocess.jl:482
```

The crash is inside JET's own `analyze_from_definitions!` -> `_which`: JET passes a method
table to `invoke_mt_compiler` that the running Julia rejects. It is a JET-internal
incompatibility, not a no-method or type error in Dendro source. JET basic is supposed to
be a hard zero-tolerance gate, so it cannot just be left off long-term.

### What is established

- Reproduces on Julia 1.11.8 (JET 0.9.20) and Julia 1.12.5 (JET 0.10). A version bump is
  not the fix.
- The base commit `26ec2bf` passes the `:jet` item on the same Julia and JET (confirmed by
  checking out a worktree there and running the item). So a definition added on this branch
  triggers it, not the environment.
- `report_package` is the fragile call; the earlier mid-session `report_package` results
  were muddied by stale precompile caches when swapping files in one session. Trust the
  `:jet` testitem (`test_package`) run in a clean process over `report_package` poked by
  hand, and clear caches between bisection steps (`rm -rf ~/.julia/compiled/v1.11/Dendro*`
  or restart the process per step).

### Reproduce

```julia
julia --startup-file=no --project=. <<'EOF'
using TestEnv; TestEnv.activate()
import JET, Dendro
try
    r = JET.report_package(Dendro; target_defined_modules = true, mode = :basic)
    println("REPORTS: ", length(JET.get_reports(r)))
catch e
    println("CRASH: ", sprint(showerror, e))
end
EOF
```

### Next steps

1. Bisect to the offending definition. The new methods are in `src/linkage.jl`,
   `src/corpus_graph.jl`, `src/placement.jl`, `src/scattered.jl`, plus the `bindings.jl` refactor
   (`collect_scopes`/`assign_defs!`/`def_kind`/`ScopeCaptures`) and `resolve.jl`. Comment
   out includes / definitions in halves, clearing the precompile cache between runs, until
   the minimal trigger is found. `analyze_from_definitions!` analyzes every method by its
   signature, so the trigger is likely one method's signature, not its body.
2. Suspect first: methods with `Function`-typed struct fields (`Linkage.resolve_target`,
   `Linkage.is_exported`) and the `LINKAGES` const holding function references; the
   `dominant(counts::AbstractDict{K}) where {K}` signature in `placement.jl`; and the
   `AbstractDict`/`AbstractVector{ParsedFile}` signatures. Try concretising or simplifying
   the minimal trigger and re-check.
3. If the trigger is innocuous Julia that JET mishandles, file a minimal upstream issue and
   either work around it (a type annotation or a `@nospecialize`) or gate the basic mode
   with a documented version/JET exclusion. Do not weaken the gate more than the minimal
   reproducer demands.
4. Restore the commented-out `@testitem "JET"` body and re-run on a stable Julia.
