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

### Duplication against a library

Every reading above judges one corpus against itself. `libraries` asks a different
question: has the author written something a library the project already ships with does
for them? Point Dendro at a dependency's source and it reports the sites in the project
that duplicate it, naming the symbol to import.

```julia
analyze("src"; libraries = [Library("IterTools", "~/.julia/packages/IterTools/A1b2C/src")])
```

```
src/util.jl:42  chunk_by  [IterTools.partition public, src/IterTools.jl:88]  library_duplicate 100 (high)
src/parse.jl:210  read_header  [HTTP.parse_line internal, src/parse.jl:44]  library_duplicate 34 (warn)
```

A library is read and never scored: it stays out of the baseline, out of the graphs, and
out of the report, so a dependency ten times the project's size neither moves the
percentile nor fills the findings with code nobody can edit. The value is how much of your
function the match covers. Only a match against a public whole library function, at or
above half coverage, reaches the `errors` floor, since that is the one case with a name to
call instead. `:library_near_duplicate` catches the copy-paste-then-edit the exact join
misses. See [the docs](https://michaelhatherly.github.io/Dendro.jl/dev/libraries/) for
configuration, the CI recipe, and the false positives worth recognising.

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
julia -m Dendro --library=IterTools=../IterTools/src src   # report duplication against a library
```

The default report ranks every function by percentile, so it is never empty, the
triage view. `--check` instead gates on the `:high` floor, the error-severity findings
(high-band scalars and all flags), so a clean codebase exits 0 and a regression exits
1. `--config=<file>` reads a config file in place of discovery, `--no-config` ignores
config files, `--cut=<float>` sets the percentile cutoff, `--library=<path>` (repeatable,
optionally `<name>=<path>`) adds a reference corpus to compare against. `--help` lists
every flag.

## Performance

Analysis parallelises across threads on a large corpus. Start Julia with `-t auto`
(or `-tN`, or set `JULIA_NUM_THREADS`) and `analyze` fans the parsing, scoring,
duplicate, and cross-file passes out over the available threads. Each pass falls
back to serial below a small size floor on its own item count (files, clone pairs,
functions), or single-threaded, so a small diff or single-file gate pays little to
no overhead. The findings are identical whatever the thread count.

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
back_edge = [90, 97]
dependency_cycle = [6, 12]

[rules]
npath = true               # enable an optional rule
parameter_count = false    # disable a built-in rule
reimplementation = true    # enable the opt-in vocabulary-overlap pass
incoherent_package = true  # enable the opt-in directory-layout pass
divisible_package = true   # enable the opt-in directory-division pass

[clones]
min_size = 12              # min named-node subtree to count as a clone
threshold = 0.9           # near-miss similarity cutoff
radius_factor = 0.5       # candidate-search radius, as a fraction of function size
library_threshold = 0.85   # cross-corpus near-miss cutoff
library_gate_coverage = 50 # coverage a public whole-unit library match needs for :high

[reimplementation]
threshold = 0.6            # vocabulary overlap a candidate pair must reach

[libraries.IterTools]
path = "~/.julia/packages/IterTools/*/src"   # a reference corpus to compare against
```

`[bands]` keys are the scalar metric names plus the relational names (`unnatural`,
`low_cohesion`, `scattered`, `split_audience`, `misplaced`, `back_edge`,
`dependency_cycle`, `hub`, `incoherent_package`, `divisible_package`); `[rules]` keys are
any rule name, plus `reimplementation`, `incoherent_package`, `divisible_package`,
`library_duplicate` and `library_near_duplicate` to gate those corpus passes; `[clones]`
and `[reimplementation]` set the duplicate- and reimplementation-detection thresholds;
`[libraries.<name>]` declares a reference corpus by `path` or `paths`, with an optional
`ignore` list. An unknown key warns and is ignored, so a typo is visible rather than
silent, except a library path matching nothing, which errors: a library resolving to
nothing would silently turn its gate off. The bands, the `cut`, the clone thresholds, the
libraries, and rule on/off are configurable; the corpus floors and model internals stay
fixed.

## Pattern rules

The built-in rules measure a fixed vocabulary of concepts. A project that wants to ban
something Dendro has no concept for writes a pattern rule: a tree-sitter query naming the
shape, and a `.dendro.toml` table saying what it means.

Declare the rule once, language-independently:

```toml
[patterns.empty_catch_binding]
message  = "`catch` with no exception binding discards the error"
severity = "high"

[patterns.magic_number]
message = "unnamed numeric literals in one function"
kind    = "scalar"
band    = [5, 10]
```

Then realise it per grammar in `.dendro/patterns/<lang>.patterns.scm`:

```scheme
; A capture names a rule. The `.not` pattern is the same pattern made more
; specific, and subtracts by node identity, which is how a rule says "without".
(catch_clause) @empty_catch_binding
(catch_clause (identifier)) @empty_catch_binding.not

; A `_` prefix marks a capture a predicate needed, never a rule of its own.
(integer_literal) @magic_number
((integer_literal) @magic_number.not (#any-of? @magic_number.not "0" "1" "2"))
```

A flag rule reports each match; a scalar rule counts its matches per unit and is scored
against its band and the corpus percentile, exactly as `cyclomatic` is. `severity`
defaults to `warn`, which keeps a new rule out of `errors`; promoting one to `high` puts
it in the gate. Findings carry the same `dendro-ignore` suppression, diff scoping, and
ratchet as every built-in.

Rules are read from `.dendro/patterns/` beside the config and from
`~/.config/dendro/patterns/` for rules shared across repositories. Both are read and
compose; where both define the same rule for the same language, the repo's wins.

A repeated shape factors out into a fragment:

```scheme
; fragment: loops = [(while_statement) (for_statement)]
@loops @any_loop
```

### When a rule is wrong, it says so

A rule that reports nothing reads as clean code, so every way of getting one wrong is
loud. A node type the grammar does not have, a bad field, a bad capture reference, or a
syntax error fails when the query compiles, naming the file and line. A predicate
TreeSitter.jl does not implement is rejected at load, since it would otherwise compile
and then silently reject every match. A capture naming no declared rule is a load error,
which catches both a typo and a helper capture that lost its `_`. An error inside a
fragment names the fragment, where it was defined, and where it was used. And a rule that
compiles cleanly but matched nothing anywhere in the corpus is reported after the scan.

### Testing a rule

Those catch a malformed rule, not one that fires on the wrong thing. Fixtures in
`.dendro/patterns/tests/<lang>.<ext>` pin both directions:

```julia
try r() catch    # dendro-expect: empty_catch_binding
end
try r() catch e  # unmarked, so the rule must not fire here
end
```

```
$ dendro --check-patterns src/
```

A marked line the rule missed fails, and so does an unmarked line it matched: checking
for false positives is the point, since a rule matching everything would pass a check
that only asked whether it matched at all.

### What a pattern rule cannot do

A query reads shape, text, and ancestry. It cannot see bindings or resolve a type, so a
rule needing either stays a Julia `Rule` passed to `analyze(path; rules = ...)`, which is
reachable from Julia but never from a config file: loading code from a repo config would
run it during a scan.

Measured against the default rule sets of Clippy, Ruff, and ESLint, 51% of a sampled 150
rules are expressible this way, with the residue split between rules needing types (17%),
formatting and ordering (23%), bindings (5%), and checks Dendro already makes (3%). The
fit is best for Python at around 70% and weakest for Rust at 44%, where linting resolves
traits.

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

A project can register a language Dendro does not ship, or replace a shipped one's query,
from its `.dendro.toml`:

```toml
[languages.zig]
extensions = ["zig"]
grammar = "/path/to/tree-sitter-zig"   # a local grammar repo, or a jll name
queries = "/path/to/my-queries"        # holds zig.scm
```

Such a language gets the per-file metrics, the structural flags, and duplicate detection.
The cross-file passes need a linkage entry in the package, so they skip it. The
[languages documentation](https://MichaelHatherly.github.io/Dendro.jl/stable/languages/)
covers the decisions a new query has to make.

## Documentation

The [documentation](https://MichaelHatherly.github.io/Dendro.jl/stable) covers the
rest: the two-score model and every metric, duplicate and near-duplicate detection,
duplication against a library the project already depends on, within-file cohesion, cross-file placement and scattering, files serving disjoint
audiences, dependencies running against a directory pair's grain, dependency cycles
reported as the edges that break them (`dependency_cycle`, banded on the number of files
caught in the cycle at `[5, 10]`), hub files by fan-in and fan-out, dead private code by
reachability, suppression directives and path ignores, custom rules, and the public API
reference.
