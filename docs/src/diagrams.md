# Diagrams

```@meta
CurrentModule = Dendro
```

To see the structure rather than read it, [`mermaid`](@ref) renders one of the graphs
Dendro builds as a mermaid `flowchart`: the reference graph behind `:misplaced` and
`:scattered`, the reachability graph behind `:unreferenced`, the clone clusters, or what
a change did to the file graph.

```julia
using Dendro: mermaid

mermaid("src"; graph = :coupling, granularity = :file)   # module-coupling map to stdout
open(io -> mermaid(io, "src"; graph = :reachability), "dead.mmd", "w")
```

A `:unit` graph of a real corpus is a hairball, one node per function, too dense to read
and too large for the standard mermaid renderer, so `focus` trims it to what the findings
touch. The default resolves that per granularity, and `focus = :all` opts back into the
full graph.

## What a change did to the shape

The other diagrams draw one revision. `graph = :change` draws two, the file graph at a
`base` git ref against the file graph at the working tree, and keeps only the edges whose
weight moved.

```julia
mermaid("src"; graph = :change, base = "main")
```

This answers the question a reviewer has before "is this code bad": did the edit stay in
one place, or did it rewire the corpus. The scalar rules already report a function that
got worse, and the architecture rules report a directory pair or a file that crossed a
band. Neither says anything about a change that adds thirty references without pushing
any single thing past a threshold, and that change may still have moved the shape.

The state of each edge is in the arrow, so the diagram survives being read without
colour:

| arrow | meaning | label |
|---|---|---|
| `==>` | added, or carrying more references than before | `new: <names>`, or `+N <names>` |
| `-.->` | fewer references than before, or gone | `-N`, or `gone` |

The label names the definitions the edge gained. "`a.jl` now depends on `b.jl`" is not
something to act on; "`a.jl` now reaches `parse_config` in `b.jl`" is. An edge that lost
references names nothing, since those definitions are gone from the working tree.

Reading one, from a change that extracted `scoring.jl` out of `report.jl`: ten rule files
each grew an edge into the new file and thinned their edge into the old one by about as
much. That paired gain and loss is what an extraction looks like, and one shape stands in
for ten hunks of diff. An edge nobody expected, or a pair of files that started pointing
at each other, is the thing to ask about.

`:change` reads git, so `paths` must sit inside a repository and `base` must name a
commit. A change that rewired nothing draws a header and no edges, which is the honest
answer rather than an empty file.

### Inside one file

A file edge is a reference that crossed a file boundary, so an edit that stays inside one
file draws nothing at all. Splitting a 200-line function into five moves plenty of
structure and moves no file edge. `granularity = :unit` reads the level below: each file's
own binding edges, one subgraph per file, the same arrows.

```julia
mermaid("src"; graph = :change, base = "main", granularity = :unit)
```

Units are matched across the two revisions by name, and then by the body digest the clone
passes already compute, so a function renamed with its body intact is one node labelled
`new (was old)` and not a deletion beside an addition. Two identical stubs renamed at once
are ambiguous, and Dendro will not guess: both report as a deletion and an addition.
Overloads merge into one node per name, since a method's position in a file moves for
reasons a reviewer does not care about.

Files are drawn heaviest mover first, and a file whose units never moved is absent rather
than drawn empty.

!!! note "This view is not yet gated"

    Every file with a moved edge is drawn, which on a large change is more diagram than
    anyone reads. Deciding which files earn a picture, and collapsing the rest behind a
    one-line summary, waits on where the output is delivered. Until then, prefer it on a
    focused diff or a single directory.

```@docs
mermaid
```
