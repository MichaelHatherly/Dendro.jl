# Dendro

Code-maintainability metrics on tree-sitter syntax trees, a cheap automatic gate
for generated code. Dendro walks the parse tree of a file, computes per-function
metrics, and scores each function two ways: against fixed absolute bands and
against the codebase's own distribution. It reads a git diff to score only the
functions a change touched.

Built on [TreeSitter.jl](https://github.com/MichaelHatherly/TreeSitter.jl).
Parsers load lazily, so Dendro depends on no language grammars itself; add the
`tree_sitter_<lang>_jll` for the languages you analyse.

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/MichaelHatherly/Dendro.jl")
# plus the grammars you want to analyse, e.g.
Pkg.add(["tree_sitter_julia_jll", "tree_sitter_python_jll"])
```

## Usage

`analyze` is the one entrypoint. Point it at a folder or a file.

Dendro exports nothing; its API is marked `public`. Import what you call, or
qualify with `Dendro.`.

```julia
using Dendro: analyze, active

# Analyse a whole project. Each function is scored against the corpus's own
# distribution, and duplicates across files are reported. The baseline is built
# from the corpus, so relative scoring works with no setup. The returned vector
# prints as a report in the REPL.
analyze("src")

# Review mode: only the functions a change touched, scored against the
# full-corpus baseline.
analyze("src"; base = "HEAD")

# Analyse one file. Language is inferred from the extension; the file's own
# functions are the corpus it is scored against.
analyze("src/parser.jl")

# Scan several roots as one corpus. A package's `src` and `ext` are measured
# together, the baseline and duplicate detection span both, and the rest of the
# tree stays out. With `base`, the repo-wide diff scopes all roots.
analyze(["src", "ext"])

# Capture the findings to filter or gate on.
findings = analyze("src")
high = filter(f -> f.absolute == :high, active(findings))
```

`analyze` returns `Findings`, a vector of `Finding`s that prints as a report. To
write that report elsewhere, `show(io, MIME("text/plain"), findings)`. A `Finding`
carries the metric, its value, the absolute band (`:ok`/`:warn`/`:high`), and the
corpus percentile:

```
src/parser.jl:1070  predicate  cyclomatic 51 (high; p100)
src/parser.jl:1070  predicate  nesting_depth 8 (high; p100)
src/api.jl:289  stub_marker (high)
```

For pull-request review, `github_annotations(io, findings)` emits the same findings
as GitHub Actions workflow commands. Each becomes an inline annotation on the diff,
high-band findings as `::error`, the rest as `::warning`:

```
::error file=src/parser.jl,line=1070,title=Dendro%3A cyclomatic::predicate: cyclomatic 51 (high; p100)
```

GitHub renders annotations only on changed lines, so pair this with `base`.
`analyze` loads each language's parser from the active environment, so the workflow
adds the `tree_sitter_<lang>_jll` for the languages it analyses. See
`.github/workflows/dendro.yml` for a working setup.

## Scoring

Every scalar metric reports two scores, and a function is flagged when either
fires:

- **Absolute**: the value against a fixed band (cyclomatic warn >10 / high >20,
  nesting >3, parameters >4). A fixed target a codebase can improve toward.
- **Relative**: the value's percentile against the corpus. Catches functions
  worse than the codebase's own norm, the signal that matters in review.

Absolute alone misses outliers in a uniformly-weak codebase; relative alone
calls a uniformly-weak codebase fine. Reporting both avoids each trap.

## Metrics

Scalar (per function): cyclomatic complexity, cognitive complexity (the same branch
points weighted by the nesting they sit under, so a deeply-nested function scores
worse than a flat one of the same path count), length, maximum nesting depth,
parameter count, boolean complexity (the most `&&`/`||` operators joined into one
expression).

Flag (presence is the finding): swallowed errors (empty catch clauses), stub
markers (`TODO`/`FIXME`/`XXX`/`HACK` comments), empty function bodies, a `return`
inside a finally clause (which discards a pending error or return value), identical
operands (`x == x`, `a && a`), and a conditional whose branches are all identical
(`if c then X else X`). An optional rule flags code after an unconditional `return`,
`break`, or `throw`.

Each metric is a [rule](#custom-rules). The set above is the default; a caller can
add their own or opt into rules that are off by default.

Relational (computed across the corpus, not per function): duplicates (below),
naturalness, and within-file cohesion. Naturalness scores each function's token
sequence against a per-language trigram model of the rest of the corpus, in bits per
token. The corpus model is interpolated with a per-file cache model (after Tu et al.,
"On the Localness of Software"), so a function is read against its own file's idiom,
not just the corpus's, which sharpens genuine outliers and quiets file-consistent
patterns. A surprising, unidiomatic function scores high, and surprise correlates
with bugs. Reported as `:unnatural` with both scores, the absolute cross-entropy band
and the corpus percentile. A language with too few tokens to model is skipped.

Cohesion asks whether a file's functions group by usage (below).

## Duplicate detection

`analyze` reports duplicates as part of a full analysis: code duplicated across
the corpus, including across different files. It hashes each subtree by its
structure, type not text, so fragments that differ only in variable names or
literal values still match (Type-2 clones). It catches the copy-paste-then-rename
that generated code produces. Detection works at two scales from the same
mechanism: a whole function duplicated, or one block, an `if` or loop body, copied
between functions that otherwise differ. A maximality filter keeps only the largest
clone, so a duplicated function is reported once, not again for every block inside
it. Each cluster of two or more comes back as one `:duplicate` finding whose
`locations` list every member:

```
src/a.jl:10  parse_header  duplicate 3 (high)
    also at src/b.jl:42  read_header
    also at src/c.jl:7  load_header
```

`min_size` (default 10 named nodes) gates out trivial functions, so one-line
getters do not cluster. Blocks must clear twice that, since a short block of
boilerplate coincides across unrelated code while a small whole function is already
a meaningful unit. Pass `min_size` lower to widen the net, higher to focus on large
clones.

### Near-misses

Exact clustering misses the copy-paste-then-edit: two functions identical but for
an added or removed statement hash differently and never meet. `analyze` also
reports these as `:near_duplicate`. It compares each function's pre-order sequence
of subtree hashes by longest common subsequence, after NiCad, scoring similarity as
`|LCS| / max(|a|, |b|)`, so functions that are close but not identical cluster when
they clear the `threshold` (default 0.85). The LCS is order-aware where a multiset
overlap is not: a reordering of the same statements, or a small fragment matching
inside a large function, scores low and is rejected. A characteristic-vector radius
query (DECKARD-style), banded by function size, finds candidate pairs without
comparing every pair; the LCS similarity confirms each one. The finding's value is
the cluster's weakest pairwise similarity as a percent:

```
src/parser.jl:40  read_header  near_duplicate 88 (high)
    also at src/loader.jl:12  load_header
```

A near-miss stays syntactic and within one language, like exact detection. Pass
`threshold` higher to demand closer matches, `radius_factor` to widen or narrow the
candidate search.

## Within-file cohesion

`analyze` reports files whose functions split into independent concerns, as
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

## Suppressing findings

Some flagged code is fine in context. A comment directive accepts a specific
finding so Dendro skips it without muting the tool or refactoring sound code.
The mechanism reads comment nodes, so it works in every supported language.

- `dendro-ignore` suppresses every finding on the same line or the line directly
  below, so a trailing comment or a comment above a declaration both work.
- `dendro-ignore: cyclomatic, parameter_count` suppresses only the named metrics.
- `dendro-ignore-file` (or `dendro-ignore-file: cyclomatic`) suppresses the whole
  file, for generated or vendored code.

```julia
# dendro-ignore: parameter_count
function build(a, b, c, d, e, f)   # one keyword per field, accepted
    ...
end
```

Metric names are the active rules' names plus the relational `duplicate` and
`near_duplicate`: by default `cyclomatic`, `cognitive_complexity`,
`function_length`, `nesting_depth`, `parameter_count`, `boolean_complexity`,
`empty_catch`, `stub_marker`, `empty_body`, `return_in_finally`,
`identical_operands`, `duplicate_branches`, `duplicate`, `near_duplicate`,
`unnatural`, `low_cohesion`. A custom rule's
name is accepted too. An unknown name warns, so a typo does not silently disable a
check. `dendro-ignore-file: low_cohesion` is the usual way to accept a file that is
meant to be a grab-bag.

Suppression marks a finding rather than dropping it. Printing a findings vector
lists the active findings and a footer counting the suppressed ones, and
`active(findings)` returns only the unsuppressed findings for gating.

## Ignoring paths

`dendro-ignore-file` mutes one file from inside it. Vendored and generated trees
you do not own want the opposite: exclusion from the outside, by path, without
touching the source. The `ignore` keyword takes gitignore-style patterns, matched
against each path relative to the scanned folder.

```julia
analyze("."; ignore = ["vendor/", "deps/**", "*.generated.jl"])
```

A leading `!` re-includes, a trailing `/` matches directories only, `*` and `?`
stop at a separator, `**` spans them. As in gitignore, a file under an excluded
directory cannot be re-included.

Ignored files are dropped before parsing, so they are neither flagged nor counted
in the baseline. This matters even in `base` review mode: an unchanged vendored
tree never appears in findings, but left in the corpus it would still skew the
percentile every scanned file feeds. Ignoring it keeps relative scoring honest.
Patterns apply to folder scans, not a single named file.

## Custom rules

A rule is a `Rule`: a metric name, its kind (`:scalar` or `:flag`), a `(warn, high)`
band for scalars, and a function that measures one unit or the file's index. The
defaults live in `BUILTIN_RULES`; pass `rules` to `analyze` to extend them.

```julia
using Dendro: analyze, Rule, BUILTIN_RULES

# A flag rule reports one finding per node it returns from (index). The index's
# concepts are the nodes the language query tagged. This one flags comments carrying
# a BUG marker.
bug_markers(index) =
    [n for n in index.comment.nodes if occursin("BUG", TreeSitter.slice(index.source, n))]

analyze("src"; rules = [BUILTIN_RULES; Rule(:bug_marker, :flag, nothing, bug_markers)])
```

A scalar rule's function is `(unit, index) -> Int`; its value is scored against the
band and the corpus percentile like any built-in. A rule reads nodes through the
index's concepts, never a node-type string, so one definition works across languages.

`OPTIONAL_RULES` holds rules that are off by default: `return_count` (return points
per function, which needs per-project band tuning), `trivial_wrapper` (a function
whose body is one delegating call, which has a higher false-positive rate), and
`npath` (NPath complexity, the count of acyclic execution paths after Nejmeh's
measure as PMD computes it: sequences multiply, branches add, each `&&`/`||` in a
condition adds a path). NPath catches the sequential-branch explosion cyclomatic and
cognitive complexity rate as moderate; its band wants per-project tuning, and it
grows multiplicatively so the count saturates rather than overflowing. NPath is not
wired for Ruby or Bash, whose branch bodies are not block nodes. Opt in with
`analyze(path; rules = [BUILTIN_RULES; OPTIONAL_RULES])`.

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

## Limitations

- Ruby swallowed-`rescue` is not flagged. Its handler body is inline rather than
  a block, so it does not fit the detection model.
- Switch `default` adds one to complexity in C, C++, and Java (default shares the
  case node) but not in Go, JavaScript, TypeScript, PHP, or Ruby (default has its
  own node).
- Go empty-body detection is weak: a Go function body always wraps a statement
  list, so empty bodies do not register.
- Metrics are syntactic. Dendro reads one file's tree with no symbol resolution,
  so cross-file concerns (unused exports, dead code across files, real coupling)
  are out of scope.
