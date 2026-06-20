# TODO

## Re-enable the JET gate

`test/jet.jl` is disabled (skipped). On the corpus-binding-graph branch, JET crashes
with `Expected MethodTableView` from its `_which` path inside `analyze_from_definitions!`.

Findings so far:
- Reproduces on Julia 1.11.8 (JET 0.9.20) and 1.12.5 (JET 0.10).
- The base commit (`26ec2bf`) passes JET on the same Julia and JET, so the trigger is
  one of this branch's definitions, not the environment.
- The crash is JET-internal (`invoke_mt_compiler(::Core.MethodTable, ...)` rejects the
  method table view JET passes), not a type error in Dendro source.

Next: bisect which new definition trips the `_which` path (binary-search the methods in
`src/linkage.jl` and `src/corpus_graph.jl`), find the minimal reproducer, and either
adjust the construct or report it upstream. Restore the commented-out gate in
`test/jet.jl` once green.

## Add a file-level `:scattered` metric

The corpus graph and community detection are in place and power `:misplaced`. A
file-level reading, "this file's units belong to several different modules", was
deferred: the corpus graph holds only cross-file edges, so a file's own units never
cluster together, and every layered file shows units spread across other files'
communities. A meaningful `:scattered` needs the within-file binding edges
(`cohesion.jl`) folded into the same graph, so a cohesive file's units form one
community and only a genuine grab-bag splits. That is a real redesign, and it overlaps
with `:low_cohesion` (within-file components) and `:misplaced` (per-unit), so scope it
carefully before building.
