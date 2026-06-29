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
three models: a splice joins included files into one namespace (Julia `include`, C
`#include`, Ruby `require_relative`); an import brings named definitions of a resolved
module in (Python, JavaScript, TypeScript, Rust, Java, PHP); a directory shares a
package's names across its files (Go). A reference that leaves its file resolves to the
definition it names in a file its linkage exposes, and the result is a corpus-wide graph
of which unit references which.

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
percentile. The finding's locations are one representative unit per elsewhere-anchored
community.

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
private when it is `static` (file-local), a Ruby method is private under a `private` or
`protected` declaration. A reference is attributed to its enclosing top-level definition by
byte range, so a call inside a nested helper or a lambda still keeps the enclosing function
alive. A name matching several definitions keeps all of them alive, since name resolution
cannot tell a type from its constructor or one method from its overload.

The reading is name-based and lexical, like the rest of placement: it matches a name to a
declared definition, never resolving a type or a dispatch. Two limits follow. It is sound
only over a whole module, so a private definition called from a same-module file outside
the scan is falsely flagged. Runtime-only entry points (a test function, a dispatch-table
callback, a string-dispatched name) carry no syntactic reference, so they are flagged
unless declared public or referenced from top level; accept one with
`dendro-ignore: unreferenced`. Java and PHP get no signal: their `private` marks a class
member, not a top-level symbol, and a package-private Java class is reached same-package
without an import the resolver sees, so flagging it would be a false positive. Their
top-level symbols stay public.
