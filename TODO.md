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
- Drop `dendro-ignore-file: unreferenced` from `file_graph.jl` once a Part II rule calls
  the layer. The directive covers definitions nothing in the package reaches; a caller
  makes it inert, and an inert directive is noise.
