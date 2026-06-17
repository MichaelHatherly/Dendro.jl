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

```julia
using Dendro

# Analyse one file. Language is inferred from the extension.
findings = analyze("src/parser.jl")
report(findings)

# Score against the codebase's own distribution, not just fixed thresholds.
baseline = build_baseline(readdir("src"; join = true))
findings = analyze("src/parser.jl"; baseline = baseline)

# Persist a baseline and reuse it.
save_baseline(baseline, "dendro-baseline.json")
baseline = load_baseline("dendro-baseline.json")

# Review mode: report only the functions a change touched.
findings = analyze_diff(; repo = ".", base = "HEAD", baseline = baseline)
report(findings)
```

A `Finding` carries the metric, its value, the absolute band (`:ok`/`:warn`/
`:high`), and, when a baseline is given, the corpus percentile:

```
src/parser.jl:1070  predicate  cyclomatic 51 (high; p100)
src/parser.jl:1070  predicate  nesting_depth 8 (high; p100)
src/api.jl:289  stub_marker (high)
```

## Scoring

Every scalar metric reports two scores, and a function is flagged when either
fires:

- **Absolute**: the value against a fixed band (cyclomatic warn >10 / high >20,
  nesting >4, parameters >5). A fixed target a codebase can improve toward.
- **Relative**: the value's percentile against the corpus. Catches functions
  worse than the codebase's own norm, the signal that matters in review.

Absolute alone misses outliers in a uniformly-weak codebase; relative alone
calls a uniformly-weak codebase fine. Reporting both avoids each trap.

## Metrics

Scalar (per function): cyclomatic complexity, length, maximum nesting depth,
parameter count.

Flag (presence is the finding): swallowed errors (empty catch clauses), stub
markers (`TODO`/`FIXME`/`XXX`/`HACK` comments), empty function bodies.

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

Metric names are Dendro's own: `cyclomatic`, `function_length`, `nesting_depth`,
`parameter_count`, `empty_catch`, `stub_marker`, `empty_body`. An unknown name
warns, so a typo does not silently disable a check.

Suppression marks a finding rather than dropping it. `report` prints the active
findings and a footer counting the suppressed ones, and `active(findings)`
returns only the unsuppressed findings for gating.

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
