# Cohesion and placement

```@meta
CurrentModule = Dendro
```

Readings of the graph of units referencing units: whether a file's functions group by
usage, whether a class's methods share state, whether a unit sits in the file it belongs
in, whether a file's units are pulled apart, who outside the file consumes what it
defines, whether a private definition is reached at all, and whether a public one says what
it does. The level above, files depending on files, is
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
functions naming the same file-local definition, not shared-field cohesion, so two
methods touching the same instance field form no edge here. The reading is weakest for a
file that is one class, where field-sharing is the main cohesion and this pass sees only
method-to-method calls. Java is the extreme, since every file is one class. That gap is
what [Class cohesion](@ref) fills, reading the fields directly.

## Class cohesion

Reported as `:divisible_class`: a class whose methods fall into several groups that share
no state, the LCOM4 reading at the level LCOM4 was defined for. Two methods are linked
when they name a field of the same instance or when one calls the other, and the score is
the number of connected components the class's methods fall into. The first location is
the class, the rest one representative method per component:

```
app/store.py:14  Store  divisible_class 15 (high; p99)
    also at app/store.py:31  read_index
    also at app/store.py:88  flush_journal
    ...
```

The fields come from a per-language capture of the use site: `self.x` and `cls.x` in
Python, `this.x` in Java, JavaScript and TypeScript, `$this->x` in PHP, `@x` in Ruby,
`self.x` and `self.0` in Rust. Java also lets a method name a field bare, so there a
reference matching a declared field name counts too, unless a local of that name shadows
it. Nothing resolves a type or a dispatch, which is what bounds the coverage: the reading
exists for the languages that put a class's methods inside the node declaring it, which is
Python, Java, JavaScript, TypeScript, PHP, Ruby and Rust. Java reads enums and records as
classes too, and PHP reads traits and enums; a Rust `impl` block is the class, named by the
type it implements rather than the trait.

The four languages left out each have a reason. A Julia struct's methods are whatever
dispatches on it anywhere in the program, which needs the dispatch resolution Dendro does
not do. Go and C put the functions acting on a type at file scope, with no container node
to read a method set off. A C++ class declares its methods and commonly defines them out of
line, so the in-class node holds almost none of the bodies and the count would measure the
header and source split rather than the class.

Constructors are dropped from the method set, and that is the one place the rule drops a
method: a constructor assigns every field a class has, so counting it would link every
group to every other and read every class as one concern. Two classes are never scored at
all. One with fewer than four methods is too small to read as several concerns. One whose
methods name no field at all has no state to divide, and there the component count is just
the method count: a static utility class, an abstract base whose methods all throw, a Rust
`impl Trait` over a unit struct.

The rule is off by default, and the reason is measurement. Across 828 classes in guava,
flask, requests, fastmcp and ripgrep the median class scores 2 or 3, so methods falling
into a few groups is what working code looks like; the per-corpus p95 runs from 5.6 to 15.5
and the p99 from 8 to 21.5, which puts the default band at `[13, 22]`. Reading guava's 29
classes at or above 13 by hand found sixteen static utility classes, abstract bases and
forwarding wrappers, where the score reads the method count; nine public API classes whose
static factories sit beside their instance methods; and three or four real god classes.
flask is cleaner at the same band, reporting its application base class and nothing else.
Nothing syntactic separates a utility class holding one constant from a class whose state
has come apart, so turn the rule on for a codebase whose classes carry state, and set the
band to what those classes look like:

```toml
[rules]
divisible_class = true

[bands]
divisible_class = [8, 15]
```

## Class size

Class cohesion asks whether a class holds several concerns. Class size asks the question a
reader asks first: does this class hold more than one class should. Both read the same
member set, and both report at the declaration line with the class name.

Reported as `:member_count`: how many definitions the class declares. Constructors count
here, where the cohesion rule drops them, since a class with fifteen constructors is what
the count is for. A nested class takes its own members, and a closure written inside a
method belongs to that method rather than to the class:

```
app/models.py:14  Order  member_count 47 (high; p99)
```

One location, not one per member. The edit the finding names is the class, and a member
list would report the same class as many times as it has members. Coverage is the seven
languages [Class cohesion](@ref) covers, for the same reason: a language earns the reading
by putting a class's methods inside the node declaring it.

The rule runs by default, banded `[20, 40]`. Twenty is the level the God-class detectors
are written around. Measurement over 5478 classes in eight corpora across six languages
puts what it costs at 7.6% of them. Forty holds 2.1%, and those are the classes nobody
argues about: laravel's 259-member `Builder`, rails' 161-member `AbstractAdapter`, guava's
91-member `LocalCache`. Only `high` reaches the floor
[`errors`](@ref) gates on, so `warn` reports without gating.

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
`private` method. A package-private *member* stays a root, reached same-package through a
receiver the resolver does not follow; it carries the `:package` visibility, which reads as
public here and only `:undocumented_public` tells apart. A Rust `pub(crate)` item reads the
same way. PHP checks only a `private` method; its classes carry no package-private privacy.

## Public definitions with no documentation

Reported as `:undocumented_public`: a declared-public top-level definition with no
documentation against it. A caller outside the corpus can reach the name and has nothing to
read about what it does. Functions, types and macros are asked after. A constant is not,
since a language documents a table of constants once at the table.

Documentation is adjacency and never content. Nothing syntactic separates a docstring that
states a contract from one restating the name above it, so the honest question is whether a
definition has one at all. A doc node on the line above a definition documents it, and so
does a docstring inside it. Rust writes `#[...]` as a sibling between the two, so the test
steps over the lines an attribute covers. A doc comment also reaches across a plain comment
line, as rustdoc, javadoc and tsc read it; a docstring does not, since Julia's parser pairs
it with the form directly below and nothing else.

Two more shapes count as documented with no doc node of their own, again because the
language's doc tool presents them so. An overriding method inherits the overridden one's
documentation. The marker is what the language writes for an override:

| language | an override is |
| --- | --- |
| Java | an `@Override` method |
| TypeScript | an `override` method |
| Python | an `@override` or `@typing.override` definition |
| PHP | a `#[\Override]` method |
| C++ | an `override` member |
| Rust | every method of an `impl Trait for` block |

A constructor is documented by its class, whichever way the language spells one
(`initialize`, `__init__`, `constructor`, `__construct`), so a bare one under an
undocumented class adds nothing to the finding the class carries.

A docstring documents a name where a doc comment documents a form. Julia's doc system shows
one docstring on every method of a generic, and Sphinx documents a function once whatever
its `typing.overload` stubs, so a definition is documented when a same-name definition in
its file carries a docstring. The sharing stops at the file, and a doc comment shares
nothing: javadoc is written per overload, and a bare overload beside a documented one is
still reported.

What counts as a doc node is each language's own convention, read off its query:

| language | documentation is |
| --- | --- |
| Julia, Python | the docstring |
| Rust | `///` and `/** */`, never `//!`, which documents the module |
| Java, JavaScript, TypeScript, PHP | a comment opening `/**` |
| Go | every `//` line above the declaration, which is what godoc takes |
| Ruby | every `#` line above the definition, which is what RDoc takes |
| C, C++ | every comment above the definition, or above a prototype of its name |
| Bash | nothing, so a bash file draws no finding |

Go and Ruby take every comment, so a `// TODO` above a function reads as documentation here
because it reads as documentation to godoc. C and C++ take every comment for the same
reason: C has no docstring, and curl and redis both document with a plain `/* */` block, so
no other convention is left to prefer. Only a docstring documents from inside: a comment
can sit anywhere in a body, and reading containment for one would let an aside in the middle
of a function answer for the function.

C and C++ declare a name apart from defining it, and curl documents at the prototype in the
header, so a definition is documented when a prototype of its name anywhere in the corpus
is. The header is also what makes it API. A non-`static` function no header (`.h`, `.hpp`,
`.hh`, `.hxx`) declares is file-local in practice whatever its linkage, so a definition is
asked after only when it sits in a header or a header declares it.

An author can also declare a name out of the documented surface, and the rule reads that
too. RDoc's `:nodoc:` on a definition's line excludes the definition, and `:nodoc: all` on a
class line excludes its members along with it; neither is reported.

The public surface is the one `:unreferenced` roots its dead-code search from, narrowed in
two places. A package-private definition, a Java method with no modifier or a Rust
`pub(crate)` or `pub(super)` item, is reachable within its package and outside the API a
caller beyond it reads, so `:unreferenced` keeps it as a root and this rule leaves it out.
And a language with no linkage entry reads as private here and public there. For
`:unreferenced` an unknown visibility read as private would hide dead code. Here it would
put a finding on every definition of a language whose public surface Dendro cannot read.

The rule ships off. A project opts in through a `.dendro.toml`:

```toml
[rules]
undocumented_public = true
```

Whether to do that is a project's own call, and the measurement is why the default is off.
Across fourteen corpora in ten languages the undocumented share of the public surface runs
from 6.7% in ripgrep to 93.8% in curl, five of them above half:

| corpus | language | public | undocumented |
| --- | --- | ---: | ---: |
| ripgrep | rust | 240 | 16 (6.7%) |
| fastmcp | python | 651 | 47 (7.2%) |
| laravel-framework | php | 14851 | 1063 (7.2%) |
| CommonMark.jl | julia | 107 | 16 (15.0%) |
| requests | python | 125 | 19 (15.2%) |
| flask | python | 100 | 22 (22.0%) |
| typescript-sdk | typescript | 97 | 23 (23.7%) |
| Dendro.jl | julia | 16 | 4 (25.0%) |
| go-sdk | go | 495 | 247 (49.9%) |
| HTTP.jl | julia | 54 | 28 (51.9%) |
| guava | java | 10124 | 6149 (60.7%) |
| rails | ruby | 4015 | 2679 (66.7%) |
| DataFrames.jl | julia | 192 | 136 (70.8%) |
| curl | c | 3768 | 3534 (93.8%) |

That spread is not a quality ordering. It is what each community documents and where. curl
documents in its headers and its manual, so its `.c` files read bare. Reading a plain
comment block takes `curl/lib` from 1491 to 1058 and `redis/src` from 3759 to 1146. The
prototype and the header gate take them to 442 and 707. Java inherits a javadoc
on every overriding method, and 5169 of guava's findings carried `@Override`. Another 1701 sat
on package-private members, the case the `:package` visibility leaves out, so with that
reading guava reports 4448 and tokio, which marks nearly everything `pub(crate)`, 5 of the
226 it reported before. Reading inherited documentation takes guava to 239 and gson from 303
to 44; the constructor reading takes activesupport from 964 to 860 and rack from 350 to 303,
and the comment step takes tokio to 1. Reading `:nodoc:` takes activesupport on to 667. Julia attaches
one docstring to a generic, so the other methods of a documented function read bare. Those
were most of DataFrames.jl's 136, and sharing a docstring across a file's same-name
definitions takes `Documenter.jl/src` from 21 to 0, `Pkg.jl/src` from 161 to 141 and
`JuliaSyntax.jl/src` from 16 to 8. Hand reading twenty of flask's findings found seven genuine; the
rest were `typing.overload` stubs, `TYPE_CHECKING` shims and a class inheriting its
documentation from a base.

So turn it on where the project's convention is a docstring on every public definition, and
expect little from it where the convention is something else. Accept one finding with
`dendro-ignore: undocumented_public`.

This shares no ground with `comment_density`, and the reason is structural. A docstring is a
string and never a comment. A doc comment sits outside the definition span, where the
per-unit fold never reaches. A project documenting entirely in docstrings scores both at
zero.
