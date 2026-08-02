# Dependencies and layout

```@meta
CurrentModule = Dendro
```

[Cohesion and placement](@ref) reads the graph of units referencing units. These rules
read the level above it: files depending on files, contracted by directory. The
resolution behind both is the same, name-based and gated by declared visibility, and
every rule here stays quiet in a language with no linkage query.

## Layout against coupling

Reported as `:incoherent_package`: a directory whose units mostly belong to communities
anchored in other directories. Placement reads those communities per unit and scattering
reads them per file; this reads them per directory, the level a repo declares its
structure at. The score is the percentage of a directory's units whose community is
anchored elsewhere, so a directory of forty units is comparable with one of four, where a
count of the communities it touches would not be. The finding's locations pair one
representative unit per elsewhere-anchored community with the unit anchoring that
community, which is how the directories the contents belong to get named.

The pass proposes a rearrangement rather than a bounded edit, and it restates per
directory much of what `:scattered` reports per file, so it is off by default and opts in
through a `.dendro.toml`:

```toml
[rules]
incoherent_package = true
```

Measured over 37 corpora, 90% of directories score zero and half a percent reach the warn
band, so a project that groups its code by what it couples to sees nothing here. A
directory holding fewer than three units is not scored: over that few, the percentage
says more about the directory's size than about its coupling. Reading the directory from
the path rather than from a declared module keeps the rule the same across languages that
have modules and languages that do not.

## Directories that outgrew one folder

Reported as `:divisible_package`: a directory holding groups of children that could become
subdirectories. Placement, scattering and layout all ask the outward question, whether code
belongs somewhere else. This asks the inward one. A directory whose contents all belong
exactly where they are can still hold several independent groups that never became folders,
and then the contents are right while the internal shape is missing.

The directory is read as its direct children over the file dependency graph, a child file as
one node and a child directory as one node with everything under it contracted in. The
communities of that induced subgraph are the candidate groups, and the score is the best
one's internal ratio as a percentage: of the reference weight its members carry inside the
directory, the share that stays inside the group. A group at 95 sends nineteen references in
twenty to its own members.

Groups are extracted, not partitioned. Whatever no folder claims stays at the top level and
is expected to, so a directory of two cohesive subsystems beside a pile of miscellaneous
files yields two folders and keeps the rest loose. The first location stands for the
directory and its label says how much of it the proposal places, so the leftover reads off
the finding. One location per proposed folder follows, each labelled with its size and its
internal ratio:

```
src/backend/constfold/pass.jl:1  [src/backend, 12 of 12 children placed]  divisible_package 100 (high)
    also at src/backend/constfold/pass.jl:1  [6 children, 100% internal]
    also at src/backend/emit/pass.jl:1  [6 children, 100% internal]
src/parser/cursor.jl:1  [src/parser, 16 of 16 children placed]  divisible_package 95 (high)
    also at src/parser/decl.jl:1  [5 children, 95% internal]
    also at src/parser/diagnostic.jl:1  [5 children, 95% internal]
    also at src/parser/cursor.jl:1  [6 children, 91% internal]
```

Both readings are in that report. `src/parser` holds sixteen loose files and divides into
three folders. `src/backend` holds twelve subdirectories and no loose files at all, and its
proposal groups those subdirectories under two new parents. Same score, same gates, same
proposal, and only the things being moved differ. Contracting a child directory into one
node is what makes one rule cover both: score a directory on its files alone and a
fully-subdivided one has no nodes and is never asked the question.

A finding proposes one level and stops. A group that itself wants dividing says so on the
next scan, once it is a directory rather than a proposal, which terminates on its own
because each level's children are fewer.

Several gates decide whether the question applies before any ratio is read. A directory
below twelve children is small enough to read at a glance and does not want subdirectories
whatever its shape. A group below five children is a family rather than a folder, so eight
groups of three stay silent even though they divide perfectly. A proposal placing less than
a quarter of the directory leaves too much loose to be worth the move, and a lone folder
covering more than seven tenths of it is a rename rather than a split. Where fewer than
three quarters of the children carry any resolved reference the rule declines to score the
directory at all: an unreferenced child is either genuinely independent or a reference the
resolver missed, and nothing syntactic tells the two apart, so a score built on the
connected part would measure the resolver rather than the code.

Two kinds of child are dropped before the groups are read. One that most of its siblings
reach for is an artifact of cross-cutting coupling rather than a subsystem, and left in it
pulls the whole directory into one group. One that names the directory it sits in
(`lib.rs`, `mod.rs`, `__init__.py`, `index.ts`) cannot move into a subdirectory of it. Both
stay at the top level, like everything else the proposal does not extract.

The pass proposes a rearrangement rather than a bounded edit, so it is off by default and
opts in through a `.dendro.toml`:

```toml
[rules]
divisible_package = true
```

The band comes from directories whose factoring is known because they were generated, not
from any corpus. Three groups of eight files read 100 when nothing crosses between them, 75
at one cross-reference per file, 59 at two and 44 at four, so warn at 60 sits just above the
level where groups are too entangled to separate without trading one tangle for another, and
high at 85 above the level where they are nearly independent. Warn is also the bar a group
clears to be proposed, so retuning the band under `[bands]` retunes what gets proposed with
it. Dendro's own `src` reads 44 over six groups and stays quiet, which is the rule declining
to call recognisable layers a modular decomposition. A directory deliberately kept flat is
accepted with `dendro-ignore: divisible_package` in the file the finding reports it at.

## Dependencies against the grain

Reported as `:back_edge`: a reference running against the direction two directories
have settled on. Placement and scattering read the corpus as units coupling to units.
This reads it one level up, as files depending on files, contracted by directory.
Between any two directories, count the reference weight each way. When `A -> B` carries
forty references and `B -> A` carries two, the code has established a direction, and
each of those two runs against it: an import to drop and a definition to move.

The score is the dominance percent, `100 * major / (major + minor)`, and higher is
worse. A pair at 60/40 is a genuinely mutual dependency, a cycle rather than a violated
grain. A pair at 98/2 is an established layering with a few references running
backwards. The layering is inferred from the corpus, so no declared layer order and no
configuration is involved. Two scores as usual, the absolute band on the dominance
percent and the percentile over the pairs that couple both ways at all, which is the
meaningful comparison. A pair whose majority direction carries too few references has
settled on no direction and is not scored, and a project whose files all sit in one
directory yields no pairs at all.

The score is a ratio, so it says the direction is one-way, never that the way back is
small. A pair with a large majority side clears a high band while still carrying dozens
of references home, and each of those is its own finding. Read how many findings a pair
produced, not the score, to judge how large the edit is.

A pair spread over more than a few file edges is therefore reported without gating: the
findings still name every edge, but none of them is error severity, whatever the
dominance. There is no single edit to propose for such a pair, and one architectural
observation should not become a dozen errors in a CI gate. It is the same treatment a
dependency cycle too tangled to cut receives.

One finding is emitted per file edge in the minority direction rather than one per pair,
since the edit is to an edge. Its locations are the import statement admitting the edge,
where the language declares one, then every reference site across it. That is wider than
a per-file metric's locations and it is deliberate: a change that adds a use of an
already-imported name introduces a back edge without touching the import's line, and a
finding located only at the import would drop out under `base` scoping. One consequence
follows in the gate. `errors(; since)` keys a finding by its location set, so adding a
reference to an established back edge re-reports it. That is the intended reading: the
ratchet catches worsening, and another reference across a back edge is worsening.

The width rule runs the other way, which is worth knowing before you rely on the gate
here. A change that adds one more back-referencing file, taking a pair just past the
width limit, demotes every finding on that pair at once: violations that were error
severity before the change stop being so, and the gate for that pair empties rather than
fills. That is the width rule working, since none of those findings names a single edit
any more, but it does mean this metric's gate contribution does not only ever grow as the
coupling gets worse. The finding count does.

Deliberate callbacks and plugin registration point backwards by design. Accept one with
`dendro-ignore: back_edge`.

## Dependency cycles

Reported as `:dependency_cycle`: a group of files that depend on one another in a loop,
read off the same file dependency graph as `:back_edge`. The shape of the finding is the
whole design here, because cycle membership on its own describes most of a real codebase.
Measured over nine corpora it covered 319 of 4528 files, and 84% of the files in the worst
of them. A rule that fires that broadly names no edit and takes the error floor with it.

So the finding is the **feedback arc set**, the edges whose removal would make the group
acyclic. The same nine corpora put seven findings in the floor. Tarjan finds the groups; each
group of two or more files then goes to the Eades-Lin-Smyth heuristic, weighted by reference
count, which sends the heavy dependencies forward so that what points backwards afterwards is
the light traffic, the cheaper edit. That heuristic bounds the size of the set it returns and
runs in linear time. It does not return a *minimum* feedback arc set, and nothing in the
report claims it does.

The score is the number of files in the group, against the absolute band and the corpus
percentile over every cyclic group's size. The percentile fired on none of the nine
calibration corpora: a corpus large enough to rank against carries enough small cycles that
they tie low, so in practice the band carries this metric.

The locations are where the two kinds of finding part. Under a handful of cuts, each location
is one edge to remove, at the import statement admitting it where the language declares one,
labelled `cut -> <target>` with the target named relative to the source file's directory:

```
src/session.jl:4  dependency_cycle 3 (warn; p80)
    cut -> render.jl
    also at src/render.jl:2  cut -> ../lib/token.jl
```

Above that many cuts the group has no bounded edit, so the locations become its
highest-degree members and every label reads `tangled: <n> cuts` instead. Reporting the
tangle rather than dropping it is the honest-over-silent call, and the label is what tells
the two kinds apart without inferring anything from how many locations there are.

The cut label is part of the key the gate ratchet matches on, which is why the target is
named relative to the source file rather than absolutely: `errors(; since)` scores the base
revision in a temporary directory, and an absolute target would re-report every cut as new.

A cycle that a language's build tolerates by design, a pair of mutually recursive modules,
is accepted with `dendro-ignore: dependency_cycle`. Like every rule over the file graph, this
one needs a linkage query for the language, and stays silent where there is none.

## Hub files

Reported as `:hub`: a file that both depends on much of the corpus and is depended on by
much of it, the Crossing anti-pattern. The reading comes from the file dependency graph,
the same resolution placement uses one level up, with nothing filtered out: the score is
`min(fan_in, fan_out)` over the count of distinct files depending on this one and the
count it depends on. The conjunction is the whole signal. Fan-in alone is every utility
module and fan-out alone every orchestrator, neither of which is a smell; a file with both
is the one that propagates every change in either direction.

The finding's first location is the file, at its first unit. When the hub's
externally-referenced definitions fall into two or more audiences, groups of definitions
linked by sharing a consumer file, one representative definition per audience follows, each
labelled with the files that consume it. That split is the proposed edit, and the labels are
what say who each half is for:

```
src/session.jl:1  hub 18 (warn; p97)
    also at src/session.jl:12  open_session  [used by api.jl, router.jl]
    also at src/session.jl:96  render_token  [used by view.jl, +3 more]
```

A label naming more than a few consumers stands for the rest with a count, so a definition
half the corpus reaches for does not turn the report into a list of paths.

A group counts as an audience only with at least two definitions and two consumer files: a
definition one file happens to use is ordinary, and a proposal built from singletons would
name every definition its own audience. A hub left with fewer than two audiences carries no
representatives: it is a warning with no proposal, and saying so beats proposing a split
that does not hold.

Because the representatives sit in the finding's locations, a change to who consumes the
file rewrites the key the gate ratchet matches on, and `errors(; since)` reports the hub
again. That is intended: the split the earlier finding proposed no longer holds.

Two scores again, and here the corpus percentile does most of the work. Fan-in and fan-out
both grow with the corpus, so the absolute band can only mark the level at which a crossing
reads as central whatever the corpus, while the rank places one file against another. The
ranked population is the files that cross at all, and a corpus below `MIN_HUB_CORPUS_FILES`
is not scored: below it every file touches most of the others and the count says nothing
about the architecture. A deliberate facade sits between two halves of a system by design;
accept one with `dendro-ignore-file: hub`.
