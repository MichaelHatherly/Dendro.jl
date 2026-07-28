# Cohesion and placement

```@meta
CurrentModule = Dendro
```

## Within-file cohesion

[`analyze`](@ref) reports files whose functions split into independent concerns, as
`:low_cohesion`. It builds a graph of a file's functions and links two when they
reference a common file-local name, a helper, type, or constant defined in the same
file. A file that breaks into several disconnected components holds that many
concerns living together, the LCOM4 reading of low cohesion. The finding's value is
the component count, and its locations are one representative function per component:

```
src/util.jl:1  parse_date  low_cohesion 3 (warn)
    also at src/util.jl:40  render_html
    also at src/util.jl:88  open_socket
```

To link on the name's binding rather than the bare string, Dendro resolves each
reference to the definition it refers to within the file (tree-sitter `locals`-style
scopes, `src/queries/<lang>.scopes.scm`). This drops the noise a string graph
carries: a local `x` in one function and a same-named `x` in another are different
bindings, and an imported or builtin name resolves to nothing. A binding referenced
by most of the file's functions is a cross-cutting utility, not a shared concern, and
links nothing. Reported with both scores, the absolute band on the component count
and the corpus percentile.

The resolution is lexical, never dispatch: an edge means two functions reference the
same file-local name, not that they call the same method. The signal stays syntactic
and within one file. Cohesion runs for every supported language; each ships a scopes
query.

The lexical line has a cost in class-based code. An edge is call linkage, two
functions naming the same file-local definition, not shared-field cohesion: with no
symbol or field resolution, methods that touch the same instance field through
different names form no edge. The reading is weakest for a file that is one class,
where field-sharing is the main cohesion and Dendro sees only method-to-method calls.
Java is the extreme, since every file is one class.

## Cross-file placement

Reported as `:misplaced`: a unit that couples more to another file than to its own. The
within-file binding resolver leaves a reference unbound when its definition lives in
another file. Placement resolves those references corpus-wide. A per-language linkage
query (`src/queries/<lang>.imports.scm`) tags how files see each other's names across
four models: a splice joins included files into one namespace (Julia `include`, C
`#include`, Ruby `require_relative`); an import brings named definitions of a resolved
module in (Python, JavaScript, TypeScript, Rust, PHP); a directory shares a package's
names across its files (Go); a package adds, on top of imports, the same-directory types a
language resolves without an import (Java). A reference that leaves its file resolves to the
definition it names in a file its linkage exposes, and the result is a corpus-wide graph
of which unit references which.

A splice carries namespaces in some languages. A definition inside a Julia `module` that
an included file declares does not join the includer's namespace: nothing reaches it by
bare name, only by qualifying it (`Mod.f`). Such a definition resolves under its qualified
name, matched on the namespace enclosing it directly, since the outer modules a reference
walks through can be declared in a file the definition's own module path never sees.

A definition at file scope answers to both forms. Its file was spliced into whatever
module the `include` sits inside, a namespace the file itself never declares, so the
corpus walks the splice chain to find the module path each file lands in. A file-scope
name is then visible bare and qualified. Reading a qualified reference this way also
stops a field read (`row.total`) resolving as a bare `total`: the two are the same syntax,
and a value's field matches no namespace.

The score is the envy percent, the share of a unit's whole coupling, own-file and
cross-file, that lands in the single other file it leans toward most. A unit devoted to
one other file scores near 100; a coordinator that reaches into several files spreads
its mass and stays low. The finding's first location is the unit, its second the
suggested home. Two scores, like cohesion: the absolute band and the corpus percentile,
fired when either trips. The deciding gate is the graph's communities (neighbourhoods,
by modularity optimisation): a unit is a candidate only when its community is anchored
in a file other than its own, the module the references say it belongs to.

Resolution is name-based and gated by declared visibility, never typed. A reference
matching several visible definitions splits its weight across them rather than picking
one by dispatch. A definition many units reach for is discounted as infrastructure, so a
shared helper does not pull every caller toward its file, the corpus analog of the
cohesion ubiquity cut. A language with no linkage query contributes no cross-file edges.

Reported as `:scattered`: a file whose units belong to several different modules, the
cross-file companion to within-file `:low_cohesion`. The corpus graph holds only
cross-file edges, so its communities alone would split every layered file. Folding each
file's within-file binding edges, the same edges cohesion links on, into the graph first
lets a cohesive file's units settle into one community, so only a file whose units are
each drawn toward a different other file scatters. The score is the count of distinct
communities the file's units occupy whose plurality anchor is another file: a file that
stays home scores zero. A bag of unrelated functions is low-cohesion but not scattered,
each its own self-anchored community; what scatters is a file each of whose units belongs
with a different other file. Two scores, like cohesion: the absolute band and the corpus
percentile.

The finding's locations are one representative unit per elsewhere-anchored community, each
labelled with the file that community is anchored in. The count is the score; the labels are
the edit:

```
src/resolution.jl:25  corpus_symbols  [belongs with mermaid.jl]  scattered 4 (warn; p96)
    also at src/resolution.jl:66  unbound_references  [belongs with bindings.jl]
    also at src/resolution.jl:166  DeclaredLinkage  [belongs with linkage.jl]
    also at src/resolution.jl:179  visible_defs  [belongs with linkage.jl]
```

Two units pulled toward the same file is the useful reading there: it says where the seam
between the two files is currently drawn wrongly. Recovering that without the labels means
rebuilding the corpus graph by hand, which is work the pass has already done.

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

## Audience splits

Reported as `:split_audience`: a file whose definitions serve two or more groups of
consumers that never overlap, the outward dual of `:low_cohesion`. Cohesion reads inward
and splits a file by the bindings its own functions share; this reads outward and splits
it by the files that consume its definitions. The two are independent: a file can share
helpers throughout, so it reads as cohesive, while serving two audiences that never meet.

For each definition something outside the file references, Dendro collects the consumer
files, links two definitions whose consumer sets meet, and takes the connected components
of that graph as the file's audiences. The score is the number of audiences holding at
least two definitions, so a helper with a single caller is not one. The band is `[3, 5]`:
across ten measured corpora 85% of scored files serve a single audience and 5% serve
three, so three separated interfaces is the tail and five is rare enough to gate on. Two
audiences is common enough that the corpus percentile carries it. The locations are one
representative definition per audience, each labelled with the files consuming that
audience, which is the split the finding proposes. A file serving a single audience names no
split, so it is never reported however unusual it is for the corpus, and it still counts
toward the distribution the percentile reads.

The audience comes from resolved references, not from declared exports. A language with
no export marker (Python, Go, C) exposes every top-level name, so an export-counting
reading would collapse into file size. A file fewer than two other files consume has one
audience by construction and is not scored at all.

## Unreferenced definitions

Reported as `:unreferenced`: a private top-level definition no path reaches from the
corpus's public surface. Dead code needs reachability, not a caller count, so a private
cluster that only calls itself is still dead. The pass builds a reference graph over every
top-level definition and walks forward from the roots. A definition is a root when it is
declared public or referenced from top-level code, which runs unconditionally. The edges
come from two sources, neither discounted: each file's within-file bindings, the same data
cohesion reads, and the cross-file references placement resolves. A definition many units
reach for is maximally alive, so unlike placement this graph drops no cross-cutting
utility and keeps definitions that are not functions.

The public surface is per language. A name in a file's `export`/`public` list is public
in Julia and JavaScript/TypeScript; a Python name is public unless it leads with an
underscore; a Go name is public when it is capitalised. A per-definition visibility
modifier covers the rest: a Rust item is public when it is `pub`, a C or C++ function is
private when it is `static` (file-local), a method is private under a Ruby `private`/
`protected` declaration or a Java or PHP `private` keyword, and a Java class is private
when it is package-private (not marked `public`). A reference is attributed to its enclosing top-level definition by
byte range, so a call inside a nested helper or a lambda still keeps the enclosing function
alive. A name matching several definitions keeps all of them alive, since name resolution
cannot tell a type from its constructor or one method from its overload.

The reading is name-based and lexical, like the rest of placement: it matches a name to a
declared definition, never resolving a type or a dispatch. Two limits follow. It is sound
only over a whole module, so a private definition called from a same-module file outside
the scan is falsely flagged. Runtime-only entry points (a test function, a dispatch-table
callback, a string-dispatched name) carry no syntactic reference, so they are flagged
unless declared public or referenced from top level; accept one with
`dendro-ignore: unreferenced`. Java resolves a same-package reference through its `:package`
linkage, so a package-private class with no user in its package is flagged alongside a
`private` method. A package-private *member* stays public, reached same-package through a
receiver the resolver does not follow. PHP checks only a `private` method; its classes
carry no package-private privacy.
