fmt:
    runic --inplace .

fmt-check:
    runic --check .

bench:
    julia --project=benchmark benchmark/run.jl

bench-quick:
    julia --project=benchmark benchmark/quick.jl

bench-profile:
    julia --project=benchmark benchmark/profile.jl

bench-save name:
    julia --project=benchmark benchmark/run.jl benchmark/results/{{name}}.json

bench-compare baseline current:
    julia --project=benchmark -e 'include("benchmark/compare.jl"); compare_and_report("benchmark/results/{{baseline}}.json", "benchmark/results/{{current}}.json", "benchmark/results/comparison.md")'
