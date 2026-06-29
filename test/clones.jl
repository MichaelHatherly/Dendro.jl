@testitem "clone_similarity is order-aware and asymmetric" tags = [:clones] begin
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 3, 4]) == 1.0
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[7, 8]) == 0.0
    # Empty inputs never arise above the size gate; guard against a NaN anyway.
    @test Dendro.clone_similarity(UInt64[], UInt64[]) == 0.0
    # A gap (one inserted node) costs proportionally: LCS 4 of the longer length 5.
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 9, 3, 4]) == 0.8
    # Order matters: a reversal shares only one element in sequence, where an
    # order-blind multiset overlap would score these identical.
    @test Dendro.clone_similarity(UInt64[1, 2, 3], UInt64[3, 2, 1]) == 1 / 3
    # A short fragment inside a long one scores low against the longer length, so the
    # verdict rejects it where a multiset overlap would not.
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[1, 2, 9, 9, 9, 9, 9, 9, 9, 9]) == 0.2
end

@testitem "clone_similarity scores near-misses below identity" setup = [Fixtures] tags = [:clones] begin
    base = "function f(x)\n    y = x + 1\n    z = y * 2\n    return z\nend\n"
    near = "function g(t)\n    a = t + 9\n    b = a * 7\n    c = b - 1\n    return c\nend\n"
    ib, inr = Fixtures.idx(:julia, base), Fixtures.idx(:julia, near)
    sf = first(Dendro.clone_features(only(Dendro.functions(ib)), ib))
    sg = first(Dendro.clone_features(only(Dendro.functions(inr)), inr))
    # `near` adds one statement, so its sequence extends `base`'s: similar, not identical.
    @test 0.5 < Dendro.clone_similarity(sf, sg) < 1.0
end

@testitem "analyze clusters near-misses across files" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, Fixtures.chain("f", 11))
        write(b, Fixtures.chain("g", 12))

        hit = only(Fixtures.near_duplicates(analyze(dir)))
        @test hit.metric == :near_duplicate
        @test hit.kind == :flag
        @test length(hit.locations) == 2
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
        # The value is the weakest pairwise Dice as a percent, above the cutoff.
        @test 85 <= hit.value < 100
    end
end

@testitem "exact clones are reported as duplicate, not near_duplicate" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 5))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 5))

        findings = analyze(dir)
        @test any(f -> f.metric == :duplicate, findings)
        @test isempty(Fixtures.near_duplicates(findings))
    end
end

@testitem "analyze does not cluster dissimilar functions" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 5))
        write(
            joinpath(dir, "b.jl"),
            "function g(x)\n    while x > 0\n        x -= 1\n        x *= 2\n        x += 3\n    end\n    return x\nend\n"
        )

        @test isempty(Fixtures.near_duplicates(analyze(dir)))
    end
end

@testitem "analyze finds near-misses across a size-band boundary" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # 58 named nodes (band 5) and 65 (band 6) straddle the power-of-two boundary;
        # the prefilter queries each band against the next so the pair is still seen.
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 7))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 8))

        @test length(Fixtures.near_duplicates(analyze(dir))) == 1
    end
end

@testitem "analyze detects near-misses within one file" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        file = joinpath(dir, "a.jl")
        write(file, string(Fixtures.chain("f", 11), Fixtures.chain("g", 12)))

        hit = only(Fixtures.near_duplicates(analyze(file)))
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testitem "analyze does not cluster near-misses across languages" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string(Fixtures.chain("f", 11), Fixtures.chain("g", 12)))
        write(joinpath(dir, "a.py"), string(Fixtures.pychain("f", 11), Fixtures.pychain("g", 12)))

        findings = Fixtures.near_duplicates(analyze(dir))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testitem "threshold gates near-misses" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 11))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 12))

        @test length(Fixtures.near_duplicates(analyze(dir))) == 1
        @test isempty(Fixtures.near_duplicates(analyze(dir; threshold = 0.95)))
    end
end

@testitem "analyze respects dendro-ignore: near_duplicate" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze, active

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string("# dendro-ignore: near_duplicate\n", Fixtures.chain("f", 11)))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 12))

        findings = analyze(dir)
        @test any(f -> f.metric == :near_duplicate && f.suppressed, findings)
        @test isempty(Fixtures.near_duplicates(active(findings)))
    end
end
