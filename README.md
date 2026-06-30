# Dendro

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://MichaelHatherly.github.io/Dendro.jl/stable)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://MichaelHatherly.github.io/Dendro.jl/dev)

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

# Capture the findings to filter or gate on.
findings = analyze("src")
high = filter(f -> f.absolute == :high, active(findings))
```

### Gating CI

`errors` is the gate companion to `analyze`. Where `analyze` ranks by percentile for
triage and so is never empty, `errors` returns only the error-severity findings, the
`:high`-band floor, so it is satisfiable: a clean codebase returns nothing. Assert it
in your test suite and every `Pkg.test()` run gates on Dendro.

```julia
@testitem "quality gate" begin
    using Dendro
    @test isempty(Dendro.errors("src"))
end
```

`analyze` returns `Findings`, a vector of `Finding`s that prints as a report. A
`Finding` carries the metric, its value, the absolute band (`:ok`/`:warn`/`:high`),
and the corpus percentile:

```
src/parser.jl:1070  predicate  cyclomatic 51 (high; p100)
src/parser.jl:1070  predicate  nesting_depth 8 (high; p100)
src/api.jl:289  stub_marker (high)
```

For pull-request review, `github_annotations(io, findings)` emits the same findings
as GitHub Actions workflow commands, recorded as pull-request check annotations.
Pair it with `base` to scope to the functions a change touched; an annotation shows
inline on the diff when its line is part of the change, otherwise in the run's Checks
tab. See `.github/workflows/dendro.yml` for a working setup.

To see the structure rather than read it, `mermaid(io, paths; graph, granularity, focus)`
renders one of the graphs Dendro builds as a mermaid `flowchart`. `graph` picks the
diagram: `:coupling` the cross-file reference graph behind `:misplaced`/`:scattered`,
`:reachability` the dead-code graph behind `:unreferenced`, `:clones` the duplicate
clusters. `granularity` is `:file` or `:unit`. Active findings overlay onto the
diagram. Redirect `io` to a `.mmd` file to save it:

```julia
using Dendro: mermaid

mermaid("src"; graph = :coupling, granularity = :file)   # module-coupling map to stdout
open(io -> mermaid(io, "src"; graph = :reachability), "dead.mmd", "w")
```

A `:unit` graph of a real corpus is a hairball: one node per function, too dense to read
and too large for the standard mermaid renderer. `focus` trims it to what the findings
touch. `:findings` keeps only flagged nodes and the `context` hops of neighbours around
them, greyed; `:all` keeps everything; `:auto` (the default) filters at `:unit` and keeps
the whole graph at `:file`. So `granularity = :unit` is readable out of the box, and
`focus = :all` opts back into the full graph.

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

## Documentation

The [documentation](https://MichaelHatherly.github.io/Dendro.jl/stable) covers the
rest: the two-score model and every metric, duplicate and near-duplicate detection,
within-file cohesion, cross-file placement and scattering, dead private code by
reachability, suppression directives and path ignores, custom rules, and the public API
reference.
