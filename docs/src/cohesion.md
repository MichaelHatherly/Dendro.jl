# Cohesion and placement

```@meta
CurrentModule = Dendro
```

Readings of the graph of units referencing units: whether a file's functions group by
usage, whether a unit sits in the file it belongs in, whether a file's units are pulled
apart, who outside the file consumes what it defines, and whether a private definition
is reached at all. The level above, files depending on files, is
[Dependencies and layout](@ref).

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
name is then visible bare and qualified, and so is a name the module's own body declares,
read from the file it includes: the two sit in one namespace, so a reference there writes
the bare name. Reading a qualified reference this way also
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
each drawn toward a different other file scatters. Every unit sharing one file-local
definition is joined to every other, and an edge's weight is how many definitions its two
units share, so calling one helper repeatedly is not read as more coupling than calling it
once. The score is the count of distinct communities the file's units occupy whose
plurality anchor is another file: a file that
stays home scores zero. A bag of unrelated functions is low-cohesion but not scattered,
each its own self-anchored community; what scatters is a file each of whose units belongs
with a different other file. Two scores, like cohesion: the absolute band and the corpus
percentile.

The finding's locations are one representative unit per elsewhere-anchored community, each
labelled with the file that community is anchored in. The count is the score; the labels are
the edit:

```
src/units.jl:11  units  [belongs with reimplementation.jl]  scattered 5 (ok; p97)
    also at src/units.jl:19  unit_span  [belongs with flags.jl]
    also at src/units.jl:30  unit_node  [belongs with flags.jl]
    also at src/units.jl:39  is_callable  [belongs with corpus_graph.jl]
    also at src/units.jl:52  is_function  [belongs with metrics.jl]
```

Two units pulled toward the same file is the useful reading there: it says where the seam
between the two files is currently drawn wrongly. Recovering that without the labels means
rebuilding the corpus graph by hand, which is work the pass has already done.

## Within-file placement

Reported as `:distant_definition`: a definition sitting a long way from the code that
uses it, the within-file companion to `:misplaced`. Where placement asks which file a
unit belongs in, this asks where in the file a definition belongs. The score is how many
top-level definitions lie between a definition and the nearest unit in its file that
references it, so a definition written beside a use scores zero. The first location is
the definition, the second the use nearest it.

```
src/linkage.jl:60  is_type_kind  distant_definition 57 (high; p99)
    also at src/linkage.jl:830  file_symbols!  [nearest use of is_type_kind]
```

Nearest rather than mean or median, and that choice is what keeps the rule quiet on a
file-wide helper without a ubiquity cut. A name most of the file reaches for has a use
close by wherever it sits, so it scores low on its own; a median would score it by the
distance to the middle of the file and report every such helper. What survives is a
definition whose uses all sit together somewhere else, which is the case with a home to
move to. Distance counts definitions rather than lines, because a reader crossing one
200-line function has crossed one thing, and `function_length` is the rule that reads
the 200.

The rule is off by default, and the reason is measurement rather than caution. Over 5798
scored definitions in nine corpora, half sit within one definition of a use, but the tail
is long: the pooled p95 is 28 and the per-corpus p95 runs from 12 to 44. Reading every
definition this package separates by 4 to 15 by hand found ordinary declaration order
throughout, a helper or a documented constant written above the one function that reads
it. Nothing syntactic separates a helper hoisted for reading order from one stranded by
an edit, so the size of the gap is all there is to read, and the default band marks only
what is beyond argument. Turn it on and set the band to the convention the project keeps:

```toml
[rules]
distant_definition = true

[bands]
distant_definition = [5, 10]
```

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
