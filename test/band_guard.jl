@testitem "a degenerate rank is withheld" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: Baseline, percentile_informs

    bl = Baseline()
    # 95 units score zero, five score one. A unit holding a single occurrence lands at
    # p95, so at the default cut every one of them would fire on rank alone.
    bl.samples[(:julia, :sparse)] = sort!(Float64[fill(0.0, 95); fill(1.0, 5)])
    @test !percentile_informs(bl, :julia, :sparse, 0.95)

    # A metric that spreads out ranks fine: one occurrence sits well below the cut.
    bl.samples[(:julia, :dense)] = sort!(Float64[i % 20 for i in 1:100])
    @test percentile_informs(bl, :julia, :dense, 0.95)

    # No samples to rank against is not a degenerate rank, it is no rank at all, and
    # `percentile` already returns nothing there.
    @test percentile_informs(bl, :julia, :absent, 0.95)
end

@testitem "a sparse metric reports on its band alone" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    # Twenty functions with no boolean operators, one with a single `&&`. Before the
    # guard the single `&&` sat above the cut and was reported for holding one operator.
    for i in 1:20
        write(joinpath(srcdir, "f$i.jl"), "function f$i(x)\n    return x\nend\n")
    end
    write(joinpath(srcdir, "g.jl"), "function g(x)\n    return x > 1 && x < 9\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hits = filter(f -> f.metric === :boolean_complexity, analyze(srcdir))
            # Nothing fires: one `&&` is far below the (4, 6) band, and the rank no
            # longer stands in for the band on a corpus that is almost all zeros.
            @test isempty(hits)
        end
    end
end

@testitem "a dense metric still ranks" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    # A spread of cyclomatic values, so the rank means something and the outlier is
    # reported on percentile even though it sits below the absolute band.
    for i in 1:20
        write(joinpath(srcdir, "f$i.jl"), Fixtures.guards("f$i", 1))
    end
    write(joinpath(srcdir, "big.jl"), Fixtures.guards("big", 9))

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hit = only(filter(f -> f.metric === :cyclomatic && f.locations[1].unit == "big", analyze(srcdir)))
            @test hit.percentile !== nothing
            @test hit.percentile >= 0.95
            # Below the (11, 21) high band, so this finding exists only because the rank
            # survived the guard. The two-score model still has both halves.
            @test hit.absolute !== :high
        end
    end
end
