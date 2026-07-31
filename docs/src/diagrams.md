# Diagrams

```@meta
CurrentModule = Dendro
```

To see the structure rather than read it, [`mermaid`](@ref) renders one of the graphs
Dendro builds as a mermaid `flowchart`: the reference graph behind `:misplaced` and
`:scattered`, the reachability graph behind `:unreferenced`, or the clone clusters.

```julia
using Dendro: mermaid

mermaid("src"; graph = :coupling, granularity = :file)   # module-coupling map to stdout
open(io -> mermaid(io, "src"; graph = :reachability), "dead.mmd", "w")
```

A `:unit` graph of a real corpus is a hairball, one node per function, too dense to read
and too large for the standard mermaid renderer, so `focus` trims it to what the findings
touch. The default resolves that per granularity, and `focus = :all` opts back into the
full graph.

```@docs
mermaid
```
