# TODO

- Share the hoisted `visible` map with `cluster_unreferenced`. `analyze` now resolves
  `corpus_visibility` once and hands it to `build_corpus_graph`, but `reach_graph`
  (`unreferenced.jl`) still calls `corpus_references(files, table)`, which resolves the
  whole corpus a second time, and `public_surface` recomputes `corpus_exports` and
  `inclusion_components` alongside it. Threading the prebuilt map through would drop one
  of the more expensive parallel passes from every scan.
