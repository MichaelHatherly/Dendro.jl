# A graph diff view for review

Status: proposed. Nothing here is implemented. The measurements below come from a
throwaway script run against this repo.
Date: 2026-08-02

## The problem

Diff scoping asks whether an edit made a function worse. Nothing asks whether an edit
moved the shape of the corpus.

The architecture rules read the graphs, but they are level-triggered. `:back_edge`,
`:hub`, `:scattered` and `:misplaced` fire when a directory pair or a file crosses a
band. A change adding forty cross-directory references without pushing any pair past a
band reports nothing, and the ratchet has nothing new to report either. Both are working
as designed: the rules answer "is this bad", and a reviewer opening a large diff asks
something before that. Did this stay in one place, or did it rewire the corpus.

Reading the code answers it badly at scale. `5eda5f8` here touched 45 files and 1138
lines. Ten of those files made one identical move. Hunk by hunk that reads as ten
separate changes to verify.

## What it is

A fourth `mermaid` view: `graph = :change`, taking a `base` git ref. Build the file graph
at base and at head, diff the edge sets, and render the changed edges.

It produces no `Finding`. It never enters `errors`, and it carries no band and no
percentile. A finding names an edit; a graph diff names an observation, and the report is
where an observation belongs. Scoring one would also mean a third score beside the
absolute band and the corpus percentile, a temporal delta against the previous revision,
which the two-score model has no room for. Keeping it in the renderer leaves that model
intact.

## What the prototype showed

`5eda5f8^` to `5eda5f8`, `src/` only, 290 edges at base and 307 at head, 62 of them
changed.

Ten rule files each gained a solid edge into the new `scoring.jl` and lost weight into
`report.jl` by about as much. Paired gain-and-loss from one source is what an extraction
looks like, and seeing it as one shape collapses ten diff hunks into one motion to check
once.

`scoring.jl` still points at `report.jl`, carrying `Finding` and `Location`. The
extraction went one way and did not invert the dependency. Answering that from the diff
means tracing two files by hand.

`units.jl` and `query_index.jl` now point at each other, both edges thickened by 8 and
17. No single hunk shows a two-way dependency between two files.

The render also showed the limit. At 62 edges the link labels already collide, so the
trimming below is not an optimisation.

## The edits

### 1. Base materialisation, factored out

`base_floor_counts` in `src/gate.jl` already verifies the ref, `git archive`s it into a
tempdir, and resolves the tempdir with `realpath` so its relative paths align with head's.
The view needs the same thing, so that block becomes a helper both call. The constraint
documented there carries over: the archive is scoped to `paths`, never the whole tree, or
the base corpus stops matching head's.

A standalone render then pays a second full parse. That is the cost the gate's ratchet
already accepts for the same reason.

### 2. Edge state in the arrow, not in colour

Mermaid styles an edge by ordinal `linkStyle N`, so colouring means counting edges as
they print, and no current view tracks an edge index. The states map onto arrow syntax
instead:

| state | arrow | label |
|---|---|---|
| added, or heavier | `==>` | `new: <names>` or `+N <names>` |
| lighter, or gone | `-.->` | `-N` or `gone` |
| untouched context | `-->` | weight |

No index bookkeeping, and it reads without colour. `FileEdge.names` supplies the
definition names, so a thickened edge says which definitions arrived rather than only
that coupling grew.

### 3. Directory subgraphs, not communities

Group the boxes with `module_graph(paths, edges, dirname)` and emit them through
`emit_subgraphs`.

The first draft justified this by asserting that modularity partitions flip wholesale
when one edge is added. Measured against this corpus, that is false. Adding one synthetic
edge to the base file graph and re-running `communities` over 27 file pairs never dropped
co-membership agreement below 96.8%, and the real commit ran at 95.8% over the 46 files
common to both revisions, 7 communities becoming 8. The partition is stable enough.

Two reasons survive that measurement. A community has no name: a box titled "community 3"
tells a reviewer nothing, and the integer itself is unstable even when membership is not,
since `renumber` assigns labels in first-seen order and one added edge relabelled 19 of
46 files in the worst trial. More important, a community box is derived from the same
edges the diagram is diffing, so a box that changes membership between base and head is
indistinguishable from the change under review. Directories hold still. Every movement
the diagram shows is then edge movement, which is the only reason to draw it.

The communities still have something to say, so they colour the nodes inside those boxes.
A `classDef` per community and a `class` line per node, the overlay mechanism the coupling
view already uses for `:misplaced` and `:scattered`.

Colour the head revision's communities and never the fact that a node's community moved.
Recolouring the movement brings back the ambiguity the boxes were changed to avoid, since
a recoloured node reads equally as the edit or as the detector re-clustering. Read as a
head-only overlay it claims nothing about the diff and only says which cluster each file
currently sits in, which is what lets an arrow crossing a box and a colour boundary read
as worse than one crossing the box alone.

The overlay earns more than it costs because a file coloured unlike its box-mates is a
file whose coupling sits outside its directory. That is `:scattered` and `:misplaced`
drawn in place, from findings already computed.

Two mechanics. Only the communities the drawn edges touch need a colour, the rest
neutral, since a palette of thirty is noise. And key the colour off something stable such
as the community's lowest-numbered file, because the raw labels renumber between
revisions and a colour that shifts for that reason is the churn this section exists to
rule out.

### 4. Trimming

Reuse `focus`, `context` and `neighbourhood`, with the flagged set being the files whose
edges changed. `:findings` already means "flagged nodes plus `context` hops, drawn greyed"
in the coupling and reachability views, and it means the same here.

### 5. Rename mapping

`git diff -M --name-status base head` maps base paths onto head paths before the edge sets
are compared. Without it a moved file draws as a rewrite: every edge in and out dotted,
then every one re-added.

## Granularity

File only, at first. Unit granularity needs a unit identity stable across revisions, and a
rename or a changed signature reads as a deletion plus an addition. `fkey` solves the
analogous problem for findings by keying on the sorted location set, so the ingredients
exist, but the diagram is legible at file level today and is not at unit level.

## Considered and set aside

A summary number: classify each changed edge by the module distance ladder the clone
clusters are already ordered by, and print what fraction stayed inside a directory. The
diagram answers that question directly for a reviewer, and a number would need a
calibration nothing supplies. Revisit only if the view goes somewhere a diagram cannot,
such as a status check.

Diffing community membership as a finding of its own. The measurement above puts a
partition move at 4% on a real commit and the community count up by one, which is too
close to what a single unrelated edge does for a reader to tell the two apart.

Gate integration. Covered above, and the ratchet already reports the findings that do
cross a band.

## Open: how the diagram reaches a reviewer

`mermaid` writes to an `IO`, and the CI workflow already redirects the annotation output
to a file. Neither answers where a diff diagram goes. Three candidates, undecided:

- A `.mmd` or `.svg` build artifact. Cheapest, and nobody opens build artifacts.
- A comment on the pull request, edited in place on each push. GitHub renders mermaid in
  comments, so the diagram arrives where the review happens. It needs a token, an edit-or-
  create dance, and a decision about what to do when the diagram is empty.
- Nothing in CI, and the view exists for local use against a branch.

This is not a detail to settle during implementation. A comment has a size budget a build
artifact does not, and that budget sets how hard the trimming in step 4 has to work. Pick
the destination before step 4, and treat the trim as sized by it.

## Open: the view inside one file

The file graph sees nothing when a change stays inside one file, since an edge is a
reference that crossed a file boundary. Splitting a 200-line function into five draws an
empty diagram. That is right for the architecture question and wrong for a reviewer, who
would still like to know the shape moved.

The material is already built. The unit graph carries each file's within-file binding
edges alongside the cross-file ones, which is what `:low_cohesion` reads as components
within one file, so a per-file unit-level change view is a diff of a structure that
exists. The identity objection that rules out unit granularity corpus-wide is weaker
inside one file, and the clone passes hash every subtree, so a unit whose name changed and
whose subtree hash did not is a rename and not a deletion plus an addition. Match on name
first and hash second.

The two granularities do not belong in one flowchart. A file edge means "references
crossed" and a unit edge means "this function calls that one", so drawing both in one
frame gives the same arrow two meanings.

Presentation is the part that decides whether this is worth building. The failure mode is
trust: a reviewer who expands fifteen diagrams and finds fourteen saying nothing stops
expanding them, and the one that mattered goes unread. So the output is a sentence per
file and the diagram is the evidence for it, drawn only when a structural predicate fires.
A within-file component splitting in two, a cycle appearing among units in one file, a
unit's fan-in falling to zero, one unit becoming the hub the rest of the file calls. Each
is a claim a sentence can make with a picture as proof. A file that changed and trips none
of them gets the line and no picture.

The rest follows from that. Collapse each diagram behind a `<details>` whose summary is
the sentence, cap how many are drawn and say how many were dropped, since a silent cap
reads as "that was everything". Scope each to the changed units plus one hop through the
same `focus` machinery, because forty units in one file is a hairball at any zoom. Keep
the arrow vocabulary identical to the corpus view, so someone who learned to read one
reads the other with no second legend.

The diff itself is built and the presentation is not. `granularity = :unit` draws every
file whose within-file edges moved, ordered heaviest mover first, with renames matched by
digest. The predicates, the one-line summary, the `<details>` and the cap all wait on the
delivery question above, since a per-file diagram is what a comment's size budget runs out
on. Until they land the view is honest and unscoped, which is fine on a focused diff and
too much on a large one.

## Sequencing

1. Factor the base helper out of `gate.jl`.
2. The `:change` view at file granularity, arrow-shape encoding, no trimming. This is
   demonstrable against this repo's own history.
3. Rename mapping.
4. Directory subgraphs and the trim.

Steps 1 and 2 are one commit. Steps 3 and 4 are one each.
