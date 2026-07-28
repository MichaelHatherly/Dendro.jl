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
- Document `:dependency_cycle` in `docs/src`. The metric name belongs in the
  `suppression.md` list a directive may name, the rule wants a section beside `:scattered`
  in `cohesion.md`, and `languages.md` should say it needs a linkage query like the other
  cross-file passes.
- Resolve `corpus_references` once per scan. `analyze` hoists `corpus_visibility` but
  `build_corpus_graph` and `build_file_graph` each walk the references themselves, so the
  resolution runs twice on every scan.
- Fold `consumer_sets` (`split_audience.jl`) into the resolution above. It walks
  `corpus_references` again to learn who references each definition, data
  `build_file_graph` already sees while it builds each edge's names. Recording a
  per-definition consumer index there would drop the walk, which `:split_audience` pays on
  every scan and `:hub` only when one fires.
- Guard the file-graph build on a corpus too small to score. `analyze` builds it on every
  scan, and `:hub` ignores a corpus below `MIN_HUB_CORPUS_FILES`, so a single-file gate run
  pays for a graph no rule reads. The floors differ per rule, so the guard belongs once
  beside the shared build rather than in each pass.
- `cluster_misplaced` and the three file-graph rules build their own findings rather than
  going through `scored_findings`. Each scores something other than a file, a unit, a
  directory pair, a cycle, or a graph node, and each reads its directives from a per-file
  dict; `:hub` also resolves its locations only for the entries that fire. They share the
  band-and-percentile reading through `two_scores` and `fires`, which is the part that is
  genuinely the same.
- `cluster_unnatural` reads its percentile over cross-entropies rather than over the
  scored value, so it uses neither `two_scores` nor `fires` while spelling out the same
  guard. Worth reconciling if the ranking key is ever unified.
