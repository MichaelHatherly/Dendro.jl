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
@testitem "Dendro quality gate" begin
    using Dendro
    errs = Dendro.errors("src"; since = get(ENV, "DENDRO_BASE", nothing))
    isempty(errs) || show(stdout, MIME"text/plain"(), errs)   # name the findings in the CI log
    @test isempty(errs)
end
```

`show` prints the per-finding report above the assertion, so a failing gate names the
functions that tripped it instead of just `Evaluated: false`.

`since` turns the floor into a ratchet: the findings at the working tree minus those at
a base git ref, the answer to "did this change introduce a violation". A finding that
predates the ref, even on a line the change touched, is not reported, which supports
adopting Dendro on a codebase that is not yet clean. Set `DENDRO_BASE` in CI to the
pull request's base (`origin/main`, the merge base) and leave it unset locally, where
`errors` falls back to the absolute floor. `since` is distinct from `analyze`'s `base`:
`base` is spatial, scoping annotations to changed lines; `since` is a finding-set
difference, the gate.

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

## Command line

`julia -m Dendro <path>...` runs the same analysis from a shell, in an environment
where Dendro is installed. It prints the report and, under `--check`, exits non-zero
when anything is reported. Installed as an app, it is the `dendro` command.

```bash
julia -m Dendro src                       # report the findings
julia -m Dendro --base=origin/main src    # only the lines a change touched
julia -m Dendro --check src               # exit 1 on any error-severity finding (CI gate)
julia -m Dendro --format=github src       # GitHub Actions annotations
```

The default report ranks every function by percentile, so it is never empty, the
triage view. `--check` instead gates on the `:high` floor, the error-severity findings
(high-band scalars and all flags), so a clean codebase exits 0 and a regression exits
1. `--config=<file>` reads a config file in place of discovery, `--no-config` ignores
config files, `--cut=<float>` sets the percentile cutoff. `--help` lists every flag.

## Performance

Analysis parallelises across threads on a large corpus. Start Julia with `-t auto`
(or `-tN`, or set `JULIA_NUM_THREADS`) and `analyze` fans the parsing, scoring,
duplicate, and cross-file passes out over the available threads. Below a small
corpus-size floor, or single-threaded, it runs serially, so a diff or single-file
gate pays no overhead. The findings are identical whatever the thread count.

```bash
julia -t auto -m Dendro src    # parallel scan on a large project
```

## Configuration

The bands a finding is judged against are drawn from common complexity guidance.
They are deliberate opinions, and a project retunes them from a `.dendro.toml` at its
repo root, no code changes. Discovery is a cascade, merged key by key, last wins: the
built-in defaults, a user-global `~/.config/dendro/config.toml`, the repo
`.dendro.toml`, then any explicit `analyze` keyword.

```toml
# .dendro.toml
cut = 0.97                 # percentile cutoff for corpus-relative flags

[bands]
cyclomatic = [15, 30]      # scalar metric: override (warn, high)
function_length = [60, 120]
low_cohesion = [5, 7]      # relational metric: override its band

[rules]
npath = true               # enable an optional rule
parameter_count = false    # disable a built-in rule

[clones]
min_size = 12              # min named-node subtree to count as a clone
threshold = 0.9           # near-miss similarity cutoff
radius_factor = 0.5       # candidate-search radius, as a fraction of function size
```

`[bands]` keys are the scalar metric names plus the four relational names
(`unnatural`, `low_cohesion`, `scattered`, `misplaced`); `[rules]` keys are any rule
name; `[clones]` sets the duplicate-detection thresholds. An unknown key warns and is
ignored, so a typo is visible rather than silent. The bands, the `cut`, the clone
thresholds, and rule on/off are configurable; the corpus floors and model internals
stay fixed.

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
