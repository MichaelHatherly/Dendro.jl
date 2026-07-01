fmt:
    runic --inplace .

fmt-check:
    runic --check .

# `-t1` pins the suite to one thread so timings stay deterministic: `analyze` fans out
# across threads above a corpus-size floor, and the calibration normalizer assumes the
# same code does the same work every run. It also overrides a shell `JULIA_NUM_THREADS`.
bench:
    julia --project=benchmark -t1 benchmark/run.jl

bench-quick:
    julia --project=benchmark -t1 benchmark/quick.jl

bench-profile:
    julia --project=benchmark -t1 benchmark/profile.jl

bench-save name:
    julia --project=benchmark -t1 benchmark/run.jl benchmark/results/{{name}}.json

bench-compare baseline current:
    julia --project=benchmark -e 'include("benchmark/compare.jl"); compare_and_report("benchmark/results/{{baseline}}.json", "benchmark/results/{{current}}.json", "benchmark/results/comparison.md")'

bench-test:
    julia --project=benchmark benchmark/test_compare.jl
