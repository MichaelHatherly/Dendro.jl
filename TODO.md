# TODO

- Share the hoisted `visible` map with `cluster_unreferenced`. `analyze` now resolves
  `corpus_visibility` once and hands it to `build_corpus_graph`, but `reach_graph`
  (`unreferenced.jl`) still calls `corpus_references(files, table)`, which resolves the
  whole corpus a second time, and `public_surface` recomputes `corpus_exports` and
  `inclusion_components` alongside it. Threading the prebuilt map through would drop one
  of the more expensive parallel passes from every scan.
- Merge `declared_targets` (`file_graph.jl`) back into `linkage.jl` beside `file_imports`
  and `include_targets`, next time `linkage.jl` is touched. It repeats their byte
  containment pairing of an `@import` region with its `@import.from` child, and exists
  apart only because neither of them returns a `Location`.
- `@run_package_tests` discovers test files in nested git worktrees. Running `Pkg.test()`
  in a checkout holding worktrees under `.claude/worktrees/` runs every copy of the
  suite, one per tree, and multiplies the reported pass count. Either exclude nested
  worktrees in the `@run_package_tests` filter or document that the suite must run from
  a clean export.
