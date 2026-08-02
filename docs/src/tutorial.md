# Your first scan

```@meta
CurrentModule = Dendro
```

Scan a project, read what comes back, decide what to act on, accept one finding, and
turn the result into something a build can fail on. The output below comes from running
Dendro over its own `src`, so your numbers will differ. The shapes will not.

## Install a grammar

Dendro depends on no language grammars. Add the ones you intend to scan:

```julia
import Pkg
Pkg.add(url = "https://github.com/MichaelHatherly/Dendro.jl")
Pkg.add("tree_sitter_julia_jll")
```

## Run it

```julia
using Dendro: analyze

findings = analyze("src")
```

That returns 440 findings on Dendro's own source and prints as a report. Nothing was
built and nothing was run: Dendro parsed the files and measured the syntax.

## Read one line

```
src/bindings.jl:110  owning_scope  cyclomatic 13 (warn; p99)
```

Left to right: where it is, the function it is about, the metric, the value, and then
two separate judgements of that value. `warn` is the fixed band, the same threshold
whatever codebase this is. `p99` is the corpus percentile, this function against the
other functions in the scan.

Two judgements because either one alone misleads. This line trips both, so it is an easy
read. The interesting case is the line that trips only one:

```
src/clones.jl:190  cluster_duplicates  function_length 41 (ok; p99)
```

Forty-one lines is unremarkable against a fixed target of fifty. It is also longer than
99% of the functions around it. Neither reading is wrong. Only the second one says this
function is unusual for the code around it. [Scoring and metrics](@ref) is why both are
kept.

## Read the top, not the whole thing

440 findings is not 440 problems. The report ranks by percentile and never comes back
empty, because its job is triage: it puts the outliers where you will see them and lets
you stop reading when the lines stop being interesting. That is the whole design. Dendro
does not decide the code is wrong, it decides where to look.

## Ask what would fail a build

The report is for a human. A gate needs a question with a satisfiable answer, and that is
a different call:

```julia
Dendro.errors("src")
```

Zero, on this source. [`errors`](@ref) returns only the error-severity findings, the
`:high` band, so a clean codebase gives back nothing and a test can assert on it. Nothing
in it depends on the corpus, so it does not move when you scan a different set of files.

## Accept one finding

Some flagged code is fine. Say so in the code, and the threshold stays where it is for
everything else:

```julia
# dendro-ignore: parameter_count
Finding(file, line, unit, metric, value, absolute, percentile, kind, suppressed) =
    Finding(metric, [Location(file, line, unit)], value, absolute, percentile, kind, suppressed)
```

Scan again and the report ends with a line like this one:

```
16 finding(s) suppressed by directives
```

Suppressed, not dropped. The count stays visible, so muting something is a decision
someone can see and revisit. A misspelt metric name warns instead of quietly doing
nothing. [Suppressing findings](@ref) covers the rest, including whole-file and by-path
exclusion.

## Ask about a change instead of a codebase

Whole-file analysis asks whether code is bad. Review asks whether an edit made it worse,
which is a better question when the diff is large and generated:

```julia
analyze("src"; base = "HEAD")
```

Only the functions the change touched, still scored against the whole corpus, so the
baseline does not shrink to the diff.

## Where to go next

- [Gating CI](@ref) turns `errors` into a test item and a pull-request annotation, and
  adds the ratchet that makes it adoptable on a codebase that is not yet clean.
- [Metric reference](@ref) lists every metric name, its default band, and whether it runs
  by default.
- [Configuration file](@ref) retunes the bands and switches rules on and off.
- [Command line](@ref) runs the same scan from a shell.
