# Dendro

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://MichaelHatherly.github.io/Dendro.jl/stable)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://MichaelHatherly.github.io/Dendro.jl/dev)

Code-maintainability metrics on tree-sitter syntax trees, a cheap automatic gate for
generated code. Dendro walks the parse tree of a file, computes per-function metrics, and
scores each function two ways: against fixed absolute bands and against the codebase's own
distribution. It reads a git diff to score only the functions a change touched.

It never builds or runs the code, so it works on a half-finished branch, on a file that
does not compile, and across a dozen languages from one set of metric definitions.

Built on [TreeSitter.jl](https://github.com/MichaelHatherly/TreeSitter.jl). Parsers load
lazily, so Dendro depends on no language grammars itself; add the `tree_sitter_<lang>_jll`
for the languages you analyse.

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/MichaelHatherly/Dendro.jl")
# plus the grammars you want to analyse, e.g.
Pkg.add(["tree_sitter_julia_jll", "tree_sitter_python_jll"])
```

## Usage

`analyze` is the one entrypoint. Point it at a folder or a file; the result prints as a
report ranked by percentile.

```julia
using Dendro: analyze

analyze("src")                  # a whole project, scored against its own distribution
analyze("src"; base = "HEAD")   # review mode: only the functions a change touched
```

```
src/parser.jl:1070  predicate  cyclomatic 51 (high; p100)
src/parser.jl:1070  predicate  nesting_depth 8 (high; p100)
src/api.jl:289  stub_marker (high)
```

`errors` is the gate companion. It returns only the error-severity findings, so a clean
codebase returns nothing and a test suite can assert on it:

```julia
@test isempty(Dendro.errors("src"; since = get(ENV, "DENDRO_BASE", nothing)))
```

`since` makes it a ratchet against a base ref, which is what lets a codebase that is not
yet clean adopt the gate.

The same analysis runs from a shell, and as the `dendro` command when installed as an app:

```bash
julia -m Dendro src              # report the findings
julia -m Dendro --check src      # exit 1 on any error-severity finding (CI gate)
```

A project retunes the bands, the percentile cut, and which rules run from a `.dendro.toml`
at its repo root, and writes rules of its own as tree-sitter queries.

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript. A project
can register one Dendro does not ship from its `.dendro.toml`.

JSON and HTML are out of scope: with no functions or control flow, these metrics do not
apply.

## Documentation

The [documentation](https://MichaelHatherly.github.io/Dendro.jl/stable) covers the rest:
the two-score model and every metric, duplicate and near-duplicate detection, duplication
against a library the project already depends on, cohesion, placement, scattering, back
edges, dependency cycles, hub files, dead private code, the CI gate and its ratchet, the
command line, configuration, suppression, custom and pattern rules, and the public API
reference.
