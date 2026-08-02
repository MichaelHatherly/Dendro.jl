# Gating CI

```@meta
CurrentModule = Dendro
```

[`errors`](@ref) is the gate companion to [`analyze`](@ref). Where [`analyze`](@ref)
ranks by percentile for triage and so is never empty, [`errors`](@ref) returns only the
error-severity findings, the `:high`-band floor, so it is satisfiable: a clean codebase
returns nothing. Assert it in your test suite and every `Pkg.test()` run gates on Dendro.

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

The floor is every finding at the `:high` absolute band: high-band scalars and all flags,
percentile-free. Nothing in it depends on the corpus distribution, so the same code gates
the same way whatever else it is scanned alongside.

## The ratchet

`since` turns the floor into a ratchet: the findings at the working tree minus those at a
base git ref, the answer to "did this change introduce a violation". A finding that
predates the ref, even on a line the change touched, is not reported, which is what makes
Dendro adoptable on a codebase that is not yet clean.

Set `DENDRO_BASE` in CI to the pull request's base (`origin/main`, or the merge base) and
leave it unset locally, where [`errors`](@ref) falls back to the absolute floor.

`since` is a keyword and not a command-line flag, so `dendro --check` reads the absolute
floor. A ratcheted gate runs from Julia, as the test item above does.

`since` is distinct from [`analyze`](@ref)'s `base`. `base` is spatial, scoping
annotations to changed lines. `since` is a finding-set difference, the gate.

## Pull-request annotations

[`github_annotations`](@ref) emits the same findings as GitHub Actions workflow commands.
GitHub records each as a pull-request check annotation, high-band findings as `::error`,
the rest as `::warning`:

```
::error file=src/parser.jl,line=1070,title=Dendro%3A cyclomatic::predicate: cyclomatic 51 (high; p100)
```

Pair this with `base` to scope findings to the functions a change touched. An annotation
renders inline on the diff when its anchored line falls in the change; otherwise it shows
in the run's Checks tab.

[`analyze`](@ref) loads each language's parser from the active environment, so the workflow
adds the `tree_sitter_<lang>_jll` for the languages it analyses. See
[`.github/workflows/dendro.yml`](https://github.com/MichaelHatherly/Dendro.jl/blob/main/.github/workflows/dendro.yml)
for a working setup.
