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
percentile score is for.

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
The moment clone detection reaches for types or call graphs, it has left the bargain.

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

Honest over silent. Inline `dendro-ignore` directives let an author accept one
finding without muting the whole tool. A suppressed finding is marked, never
dropped, so the count stays visible and a typo'd metric name warns. The moment
suppression hides things silently, it stops being worth trusting.

Dendro eats its own cooking. It runs on its own source (`test/dogfood.jl`) and
must come back clean. If a change makes Dendro trip its own metrics, fix the code,
not the test.

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
