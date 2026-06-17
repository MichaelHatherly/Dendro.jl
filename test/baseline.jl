@testset "percentile" begin
    b = Dendro.Baseline(Dict((:julia, :cyclomatic) => Float64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    @test Dendro.percentile(b, :julia, :cyclomatic, 5) == 0.5
    @test Dendro.percentile(b, :julia, :cyclomatic, 10) == 1.0
    @test Dendro.percentile(b, :julia, :cyclomatic, 100) == 1.0
    # No samples recorded for this metric, so there is nothing to rank against.
    @test Dendro.percentile(b, :julia, :nesting_depth, 3) === nothing
end

@testset "build_baseline (julia)" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "function s(x)\n    x + 1\nend\n")
    write(joinpath(dir, "b.jl"), "function t(x)\n    if x > 0\n        1\n    else\n        2\n    end\nend\n")

    b = Dendro.build_baseline([joinpath(dir, "a.jl"), joinpath(dir, "b.jl")])
    cyc = b.samples[(:julia, :cyclomatic)]
    @test length(cyc) == 2
    @test cyc == [1.0, 2.0]
    @test Dendro.percentile(b, :julia, :cyclomatic, 2) == 1.0

    # Files with no profile are skipped, not errored on.
    write(joinpath(dir, "notes.md"), "# not code\n")
    b2 = Dendro.build_baseline([joinpath(dir, "notes.md")])
    @test isempty(b2.samples)
end

@testset "baseline json round-trip" begin
    b = Dendro.Baseline(Dict(
        (:julia, :cyclomatic) => Float64[1, 2, 3],
        (:julia, :nesting_depth) => Float64[0, 1],
    ))
    path = joinpath(mktempdir(), "base.json")
    Dendro.save_baseline(b, path)
    b2 = Dendro.load_baseline(path)
    @test b2.samples == b.samples
end
