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

Syntactic and shallow, on purpose. Dendro reads one file's tree with no symbol
resolution. That is what keeps it cheap and language-agnostic. Cross-file concerns
like dead code, real coupling, and unused exports are out of scope by design.
Resist requests to make a metric smarter by reaching outside the file.

Languages are data. A `LanguageProfile` maps abstract concepts (decision points,
nesting, comments, catch clauses) to a language's concrete node types. Adding a
language is a profile plus an extension entry. If you find yourself special-casing
a language inside metric code, the profile is missing a field.

The diff is the question. Whole-file analysis asks whether code is bad.
Diff-scoping asks whether an edit made it worse, which is what review actually
wants to know. That is why `analyze_diff` exists.

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
