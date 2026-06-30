# Tests for the comparison gate and runner-speed normalizer.
#
# Run with: julia --project=benchmark benchmark/test_compare.jl

using Test

include("compare.jl")

# Build a single benchmark entry shaped like the stored JSON.
bench(; time_ns, memory, allocs) = Dict(
    "time_ns" => Dict("median" => Float64(time_ns)),
    "memory_bytes" => memory,
    "allocations" => allocs,
)

# Wrap benchmark entries in a full result document with a calibration kernel.
doc(benchmarks; calibration_ns) = Dict(
    "benchmarks" =>
        merge(benchmarks, Dict("calibration" => bench(; time_ns = calibration_ns, memory = 0, allocs = 0))),
)

@testset "normalization_factor" begin
    # Same calibration time on both sides: factor is 1.
    base = doc(Dict(); calibration_ns = 1.0e6)
    curr = doc(Dict(); calibration_ns = 1.0e6)
    @test normalization_factor(base, curr) ≈ 1.0

    # Current runner 25% slower (calibration 25% higher): factor scales current back down.
    slow = doc(Dict(); calibration_ns = 1.25e6)
    @test normalization_factor(base, slow) ≈ 0.8

    # Missing calibration on either side disables normalization.
    @test normalization_factor(Dict("benchmarks" => Dict()), curr) == 1.0
    @test normalization_factor(base, Dict("benchmarks" => Dict())) == 1.0
end

@testset "classify" begin
    # Allocation regression: deterministic signal fires regardless of timing noise.
    b = bench(; time_ns = 100, memory = 1000, allocs = 1000)
    c = bench(; time_ns = 100, memory = 1000, allocs = 1150)
    r = classify(b, c; factor = 1.0)
    @test r.status == :regression
    @test r.signal == :allocations

    # Pure runner noise: allocations identical, raw time up 28%, but the runner is
    # 28% slower (factor 1/1.28), so normalized time is flat. Verdict is neutral.
    b = bench(; time_ns = 100, memory = 1000, allocs = 1000)
    c = bench(; time_ns = 128, memory = 1000, allocs = 1000)
    r = classify(b, c; factor = 1.0 / 1.28)
    @test r.status == :neutral

    # Compute regression: allocations and memory flat, runner speed flat, but the
    # work takes 20% longer. Normalized time catches what allocations cannot.
    b = bench(; time_ns = 100, memory = 1000, allocs = 1000)
    c = bench(; time_ns = 120, memory = 1000, allocs = 1000)
    r = classify(b, c; factor = 1.0)
    @test r.status == :regression
    @test r.signal == :time

    # Improvement: allocations drop.
    b = bench(; time_ns = 100, memory = 1000, allocs = 1000)
    c = bench(; time_ns = 100, memory = 1000, allocs = 800)
    r = classify(b, c; factor = 1.0)
    @test r.status == :improvement
    @test r.signal == :allocations

    # Within tolerance on every axis: neutral.
    b = bench(; time_ns = 1000, memory = 1000, allocs = 1000)
    c = bench(; time_ns = 1005, memory = 1000, allocs = 1000)
    r = classify(b, c; factor = 1.0)
    @test r.status == :neutral
end
