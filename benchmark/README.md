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
