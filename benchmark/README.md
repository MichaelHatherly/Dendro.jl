# Benchmarks for Dendro.jl

Continuous benchmarking tracks performance over time. Results are stored on the
`gh-pages` branch and visualized via GitHub Pages.

## Running locally

```bash
# Run the full suite (terminal output)
just bench

# Quick single-target measurement for iteration
just bench-quick

# Profile analysis to find hot spots (writes benchmark/profile.txt)
just bench-profile

# Save a baseline before making changes
just bench-save baseline

# Make changes, then save the current state
just bench-save current

# Compare two saved results
just bench-compare baseline current
```

## Benchmark suite

The suite in `benchmarks.jl` is built for stable trends. Inputs whose size tracks
the codebase would confound a historical comparison, so `src/` is not an input.

- **analyze/corpus** — the public `analyze` pipeline over the whole `test/corpus`
  tree. The realistic, multi-language end-to-end number. Drifts only when a fixture
  is added.
- **parse/\<lang\>** — parse, query, and binding resolution for one fixed fixture
  file per language. Isolates per-language parser cost.
- **stages/** — the clustering passes (`baseline`, `clones_exact`, `clones_near`,
  `naturalness`, `cohesion`) over a synthetic corpus of a pinned size. The synthetic
  corpus is deterministic and fixed, so a movement here is the algorithm, not the
  input. This is where a regression in the near-miss radius query or LCS shows up.

The synthetic corpus seeds exact clones and near-misses across several size bands so
the duplicate passes do real work. Its size is `SYNTH_N` in `benchmarks.jl`.

- **calibration** — a fixed, allocation-free compute kernel of a pinned iteration
  count. It does identical work every run, so its wall-clock is a direct read of how
  fast the runner was that day. `compare.jl` divides it out to separate a code change
  from a slower runner. The iteration count is fixed forever; changing it rebases
  every future comparison against a different clock.

## Gate and normalizer

A shared CI runner has no performance isolation: the same code can run 20% slower on
a different day. Two defences keep that noise out of the verdict.

The **gate** decides regressions on allocations and memory first. Those are
deterministic, the same code over the same input always allocates the same, so a
change past 1% is real, never noise. Time decides only when allocations and memory
are flat, which catches a compute regression that touches no allocation.

The **normalizer** removes runner-speed drift from that time signal. Each run measures
the `calibration` kernel; `compare.jl` scales the current run's times by the ratio of
the two calibration medians before applying its 10% band. A run on a 20%-slower runner
no longer reads as a 20% regression.

The suite runs **single-threaded**. `analyze` fans out across threads above a per-pass
size floor, which makes timings nondeterministic and breaks the normalizer's same-work
assumption. The `just bench*` recipes pass `-t1`, and `benchmarks.jl` errors if started
with more than one thread. To benchmark the threaded path, measure `analyze` directly
outside this suite.

Run the tooling tests with `just bench-test`.

## CI workflow

- **Push to `main`**: results stored on the `gh-pages` branch under `benchmarks/`.
- **Pull requests**: the suite runs on both the base and the head commit on the
  same runner, and a comparison is posted as a PR comment and the job summary.
- **Visualization**: https://michaelhatherly.github.io/Dendro.jl/benchmarks/

## Comparing results

```bash
julia --project=benchmark -e '
    include("benchmark/compare.jl")
    compare_and_report("baseline.json", "current.json", "comparison.md")
'
```
