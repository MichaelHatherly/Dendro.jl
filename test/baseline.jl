@testitem "percentile" tags = [:baseline] begin
    b = Dendro.Baseline(Dict((:julia, :cyclomatic) => Float64[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    @test Dendro.percentile(b, :julia, :cyclomatic, 5) == 0.5
    @test Dendro.percentile(b, :julia, :cyclomatic, 10) == 1.0
    @test Dendro.percentile(b, :julia, :cyclomatic, 100) == 1.0
    # No samples recorded for this metric, so there is nothing to rank against.
    @test Dendro.percentile(b, :julia, :nesting_depth, 3) === nothing
end

@testitem "baseline_from accumulates corpus samples" tags = [:baseline] begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function s(x)\n    x + 1\nend\n")
        write(joinpath(dir, "b.jl"), "function t(x)\n    if x > 0\n        1\n    else\n        2\n    end\nend\n")

        files = Dendro.parse_corpus([joinpath(dir, "a.jl"), joinpath(dir, "b.jl")])
        b = Dendro.baseline_from(files)
        cyc = b.samples[(:julia, :cyclomatic)]
        @test length(cyc) == 2
        @test cyc == [1.0, 2.0]
        @test Dendro.percentile(b, :julia, :cyclomatic, 2) == 1.0
    end
end
