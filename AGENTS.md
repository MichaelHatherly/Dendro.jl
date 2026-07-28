# Project instructions for AI assistants

## What Dendro is for

A cheap, automatic gate for generated code. An agent can emit a 200-line function
with five levels of nesting and a swallowed exception, and nothing complains.
Dendro complains. It parses a file, measures each function, and flags the ones
worth a second look, fast enough to run on every diff.

The point is leverage on review attention. A human reviewing a large generated
diff cannot read every function with equal care. Dendro narrows the field: here
are the three functions that got long, the catch that swallows, the body that
does nothing. It does not decide the code is wrong. It decides where to look.

Why tree-sitter and not a real compiler: Dendro never builds or runs the code. It
reads syntax. That means it works on a half-finished branch, on a file that does
not compile, and across a dozen languages from one set of metric definitions. The
cost is that every metric is a structural approximation, complexity by counting
branch nodes, not by analysing control flow. Cheap and broad over precise and
deep is the whole bargain. When a change tempts you to trade it away, that is the
thing to protect.

## The ideas that shape the code

Two scores, not one. Every scalar metric is judged against a fixed absolute band
and against the codebase's own distribution. Absolute alone misses outliers in a
uniformly-weak codebase. Relative alone calls a uniformly-weak codebase fine. A
function is flagged when either fires. Keep both. Dropping one reintroduces the
trap it closes.

The fixed bands are a standard, not a measurement. They are deliberate targets
drawn from common complexity guidance, so a weak codebase has something to improve
toward rather than only its own median to match. They are opinions, and opinions
can be retuned, but they are never derived from the corpus. The corpus is what the
percentile score is for. A project retunes them in a `.dendro.toml` at its root,
the cascade resolved in `config.jl`: built-in defaults, then a user-global config,
then the repo file, then explicit `analyze` keywords, merged key by key. Only the
flagging opinions are configurable: the bands, the percentile cut, the clone-detection
thresholds, and which rules are active. The corpus floors and the model internals are
not. An unknown key warns rather than failing, the same honest-over-silent stance as a
typo'd `dendro-ignore`.

Syntactic and shallow, on purpose. Dendro reads tree shape and resolves names
lexically, never types. It matches a reference to the definition it lexically names,
within a file and, along declared `include`/`import`/`export` edges, across files, but
it never works out a name's type or which method a call dispatches to. That is what
keeps it cheap and language-agnostic. Concerns that need type or dispatch resolution,
real call graphs, overload resolution, are out of scope by design. Dead code is out of
scope for declared-public symbols, where reachability would need a real call graph;
unreferenced private definitions are flagged via reachability from the public surface,
name-based and lexical, no types or dispatch. The line is type and dispatch resolution,
not the file boundary and not name
resolution: matching a name to a declared definition is fine, working out its type is
not. Resist requests to make a metric smarter by reaching for types or dispatch instead
of shape and name.

Languages are data. A tree-sitter query (`src/queries/<lang>.scm`) maps abstract
concepts (decision points, nesting, comments, catch clauses) to a language's
concrete node types, tagging each with a capture; one pass builds a `QueryIndex` the
metrics read. Adding a language is a query, a `PROFILES` entry, and an extension
entry. If you find yourself special-casing a language inside metric code, the query
is missing a capture.

The diff is the question. Whole-file analysis asks whether code is bad.
Diff-scoping asks whether an edit made it worse, which is what review actually
wants to know. That is why `analyze` takes a `base` git ref.

Duplicates are structure, not meaning. Dendro flags code duplicated across the
corpus, exact clones and near-misses both, a whole function or one block copied
between functions. This crosses the single-file boundary, but it never resolves a
symbol: it compares subtree hashes and tree shape, nothing more. Exact detection
indexes every subtree and keeps only the maximal clone, so a duplicated function is
not also reported as each block inside it. Near-miss detection compares the pre-order
subtree-hash sequences by longest common subsequence (after NiCad) and runs a
size-banded vector query only to propose candidate pairs. The query is a prefilter;
the LCS similarity is the verdict, order-aware where a multiset overlap is not. Keep
that split, keep clone detection within one language, and keep the block size floor
above the function floor: small blocks of boilerplate coincide and turn into noise.
A control-free whole function is boilerplate too, a dispatch stub or forwarding
overload, so it clears the block floor, not the function floor. Only a function with
control flow is a meaningful unit at the lower floor.
The moment clone detection reaches for types or call graphs, it has left the bargain.

Reimplementation candidates are vocabulary, still not meaning. A helper rewritten
with a different shape shares no subtrees with the original, so the clone passes miss
it; what survives a rewrite is the vocabulary, the callee names and identifier words,
and that is all this pass reads. Terms are weighted by rarity in the scanned corpus,
computed at scan time, and that is the line to hold: corpus-derived statistics are
inside the tent (the trigram model set the precedent), pretrained weights are not,
because they import opinions the finding cannot explain. Vocabulary evidence is
proposal-strength rather than measurement, so the pass is off by default, and a pair
the clone passes report is never repeated here. Keep the gates (clone handoff,
caller/callee, same name, size ratio), keep it within one language, and expect
deliberately parallel families of substantial logic, per-language resolvers and the
like, to pair: that is the mechanism working, answered with a suppression, not a
smarter model. Trivial parallel shapes are the clone floor's job now, not a
suppression's.

Placement is structure across files, still not meaning. Dendro resolves a reference
that leaves its file to the definition it names in another file, along declared
`include`/`import`/`export` edges, and builds a corpus-wide graph of which unit
references which. A reference is matched by name and gated by what its file can see; a
name that matches several visible definitions splits its weight, never picking one by
type or dispatch. A unit whose coupling lands mostly in one other file is flagged
`:misplaced`, with that file as its suggested home, and the graph's communities
(neighbourhoods, by modularity) are the deciding gate. A definition many units reach
for is discounted as infrastructure rather than chased into a call graph, the corpus
analog of the cohesion ubiquity cut. Keep the resolution name-based, keep it gated by
declared visibility, keep the cross-cutting discount, and add a language's linkage as a
query (`src/queries/<lang>.imports.scm`) plus a `LINKAGES` entry, never a special case
in the graph code. The moment placement resolves a name by its type, it has left the
bargain.

Scattering is placement read per file. The same graph carries each file's within-file
binding edges alongside the cross-file ones; reading the view that folds the within edges
in lets a cohesive file's units cluster together, and the score is how many different
modules a file's units are pulled toward. A file whose units each belong with a different
other file is flagged `:scattered`, the cross-file companion to within-file
`:low_cohesion`. The fold-in is load-bearing: the cross-file edges alone leave a file's
units unlinked to each other, so every layered file would look scattered. Keep the
within-file edges in the graph, read them folded in for scattering and as components
within one file for cohesion, keep the score the count of communities a file's units
occupy that are anchored elsewhere, and keep it name-based and lexical like the rest of
placement.

The file graph is that resolution read one level up. Placement asks where a unit belongs;
the file graph asks which file depends on which. Nodes are corpus files, an edge counts the
references crossing from one to another, and it carries the definition names behind it and
the import statement that admits it, so a finding built on it names an edit rather than a
score. It reads unfiltered references where placement drops the cross-cutting ones. That
cut is right for placement, since without it a unit is judged to belong wherever a shared
helper lives, and wrong here, since a file everything reaches for is the observation an
architecture question is after. So it is a separate constructor over the same primitives,
not a mode flag on `build_corpus_graph`: one function serving both notions of an edge
leaves every reader working out which one a call site meant. Everything else holds.
Name-based and lexical, gated by declared visibility, a name matching several definitions
splits its weight, no types and no dispatch. Contract it by directory (`module_graph`) for
a question about packages, not by a declared module, which some languages have and some do
not, so the same rule would fire differently across a polyglot corpus for reasons unrelated
to the code. An import statement is evidence on an edge, never an edge on its own: the
dependency is the reference that crossed, and that is where the bargain's line sits here.

Grain is the first question asked of that graph. Between two directories, count the
reference weight each way: when one direction carries nearly all of it, the code has
established a direction and the references going back run against it, each one an import
to drop and a definition to move. `:back_edge` reads that, inferring the layering from the
corpus rather than from a declared layer map nobody maintains. Higher dominance is worse,
because a pair that couples both ways in earnest is a cycle rather than a violated grain.
The score is a ratio, so it never bounds the size of the resulting edit: a pair with a
large majority side clears the band while still carrying dozens of references home, one
finding each. The location count says how big the edit is; the score does not.
Its locations are the import statement and then every reference across the edge, which is
wider than any per-file metric's and is what lets a diff that adds a use of an
already-imported name still scope the finding in. The consequence, that the gate ratchet
re-reports a back edge each time a reference joins it, is the behaviour wanted and not a
defect: one more reference across a back edge is worsening, and the ratchet is there to
catch worsening. Deliberate callbacks and plugin registration point backwards on purpose;
answer those with a suppression, not a smarter model.

A hub is that graph read per file. A file both depended on by much of the corpus and
depending on much of it propagates every change in either direction, so `:hub` scores
`min(fan_in, fan_out)` over distinct files and nothing else: fan-in alone is every utility
and fan-out alone every orchestrator, and only the conjunction names the file in the
middle. Keep the `min`. The proposal is the split, the hub's definitions grouped by who
consumes them, and a hub whose consumers all reach the whole file is reported as a warning
with no proposal rather than dressed up as one. Both counts grow with the corpus, so the
absolute band here is weaker than any per-function one and the percentile carries most of
the weight, which is the two-score model earning its place rather than a defect to tune
away.

Honest over silent. Inline `dendro-ignore` directives let an author accept one
finding without muting the whole tool. A suppressed finding is marked, never
dropped, so the count stays visible and a typo'd metric name warns. The moment
suppression hides things silently, it stops being worth trusting.

Dendro eats its own cooking. `test/dogfood.jl` asserts `isempty(Dendro.errors(src))`,
the deterministic error floor: every finding at the `:high` absolute band, high-band
scalars and all flags, percentile-free. This is a superset of the old hand-listed
metrics, so it auto-adopts any future high-band metric. Two `parameter_count` sites
trip it, the `Finding` constructor and `mermaid_coupling`, where the parameter count
tracks a struct's fields or a genuine set of rendering inputs. Both carry inline
`dendro-ignore: parameter_count`, suppressed not omitted, so the count stays honest
and the floor reports them as suppressed. If a change makes Dendro trip its own
metrics, fix the code, not the test.

## Where the details live

- How the pieces fit, the data types, the flow through a scan: `ARCHITECTURE.md`.
  That is the source of truth for structure. Read it before a non-trivial change,
  and update it when the structure moves.
- Behaviour, scoring, metrics, languages, limitations: `README.md`.
- Per-symbol contracts: docstrings in `src/`, exercised by `test/`.
- Run the suite: `julia --project=. -e 'using Pkg; Pkg.test()'`. Language parsers
  live in `test/Project.toml`, so parsing only works under `Pkg.test()`, not a
  bare package-env REPL. Redirect test output to a file and read it on failure.
  The suite is [TestItemRunner](https://github.com/julia-vscode/TestItemRunner.jl):
  each check is a tagged `@testitem`, shared helpers live in `@testmodule Fixtures`
  (`test/setup.jl`), reached qualified as `Fixtures.idx(...)`. Items run in any
  order, each in its own module.
  The `:jet` item runs [JET](https://github.com/aviatesk/JET.jl) static analysis
  (`test/jet.jl`): basic mode is a zero-tolerance gate on every stable Julia version
  (JET ships only a stub on pre-release Julia, so the item skips there), so a
  type-level regression fails the run. Sound mode and the optimization analyzer are
  ratcheted instead: their report counts are capped at the current value and may only
  fall. Lower a limit (`SOUND_LIMIT`, `OPT_LIMIT`) when reports are trimmed; the suite
  prints the new value when a count drops. The ratchet is pinned to one Julia version,
  since JET counts shift across versions.
- Format with [Runic](https://github.com/fredrikekre/Runic.jl). CI checks it.

  ```bash
  just fmt        # format in-place with Runic
  just fmt-check  # check formatting without modifying (CI)
  ```
