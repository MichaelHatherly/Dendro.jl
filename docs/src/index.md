# Dendro.jl

```@meta
CurrentModule = Dendro
```

Code-maintainability metrics on tree-sitter syntax trees, a cheap automatic gate
for generated code. Dendro walks the parse tree of a file, computes per-function
metrics, and scores each function two ways: against fixed absolute bands and against
the codebase's own distribution. Point it at a git diff and it scores only the
functions a change touched.

Dendro never builds or runs the code. It reads syntax, so it works on a
half-finished branch, on a file that does not compile, and across a dozen languages
from one set of metric definitions. Every metric is a structural approximation:
complexity by counting branch nodes, not by analysing control flow. Cheap and broad
over precise and deep.

Built on [TreeSitter.jl](https://github.com/MichaelHatherly/TreeSitter.jl). Parsers
load lazily, so Dendro depends on no language grammars itself. Add the
`tree_sitter_<lang>_jll` for the languages you analyse.

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/MichaelHatherly/Dendro.jl")
# plus the grammars you want to analyse, e.g.
Pkg.add(["tree_sitter_julia_jll", "tree_sitter_python_jll"])
```

## Usage

[`analyze`](@ref) is the one entrypoint. Point it at a folder or a file.

Dendro exports nothing; its API is marked `public`. Import what you call, or qualify
with `Dendro.`.

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

[`analyze`](@ref) returns [`Findings`](@ref), a vector of [`Finding`](@ref)s that
prints as a report. To write that report elsewhere, `show(io, MIME("text/plain"),
findings)`. A [`Finding`](@ref) carries the metric, its value, the absolute band
(`:ok`/`:warn`/`:high`), and the corpus percentile:

```
src/parser.jl:1070  predicate  cyclomatic 51 (high; p100)
src/parser.jl:1070  predicate  nesting_depth 8 (high; p100)
src/api.jl:289  stub_marker (high)
```

[`errors`](@ref) is the gate companion: only the error-severity findings, so a clean
codebase returns nothing and a test suite can assert on it. [Gating CI](@ref) covers it,
the ratchet against a base ref, and the pull-request annotations.

## Where to read next

- [Scoring and metrics](@ref) explains the two-score model and what each metric measures.
- [Metric reference](@ref) tabulates every metric name, its default band, and whether it runs by default.
- [Duplicate detection](@ref) covers exact clones and near-misses across the corpus.
- [Duplication against a library](@ref) asks whether a dependency already does it.
- [Comparing against a library](@ref) sets one up, in a config file or in CI.
- [Cohesion and placement](@ref) covers cohesion, placement, scattering, audiences, and dead private code.
- [Dependencies and layout](@ref) covers hubs, back edges, cycles, and directory shape.
- [Diagrams](@ref) renders those graphs as mermaid flowcharts.
- [Gating CI](@ref) is the error floor, the ratchet, and the GitHub Actions setup.
- [Command line](@ref) documents `julia -m Dendro`, its flags, and threading.
- [Configuration file](@ref) is the `.dendro.toml` cascade and every key it takes.
- [Suppressing findings](@ref) is about the inline directives and path ignores.
- [Custom rules](@ref) shows how to extend or replace the rule set.
- [Pattern rules](patterns.md) writes a project's own rule as a tree-sitter query.
- [Languages and limitations](@ref) lists what is supported and where the bargain shows.
- [API reference](@ref) documents every public function and type.
