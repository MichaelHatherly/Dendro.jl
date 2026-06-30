# The quality gate: `errors` is the gate-severity subset of findings. These items
# pin the deterministic floor (high-band scalars and all flags), so a percentile-only
# finding, which always exists, can never fail the gate.

@testitem "quality gate: floor" tags = [:gate] begin
    using Dendro

    # An over-band function and a merely-warn function, in a corpus small enough that
    # the warn value and an unrelated :ok value both rank p100. The floor keeps the
    # high-band finding and drops both the warn and the percentile-only ones.
    dir = mktempdir()
    write(
        joinpath(dir, "a.jl"), """
        function fa(x)
            if x > 0
                if x > 1
                    if x > 2
                        if x > 3
                            if x > 4
                                if x > 5
                                    return x
                                end
                            end
                        end
                    end
                end
            end
        end
        """
    )
    write(
        joinpath(dir, "b.jl"), """
        function fb(a, b, c, d, e)
            return a
        end
        """
    )

    found = Dendro.active(Dendro.analyze(dir))
    # Sanity: analyze surfaces the warn and percentile-only findings the floor must drop,
    # so the floor is filtering them out, not merely never seeing them.
    @test any(f -> f.metric == :parameter_count && f.absolute == :warn, found)
    @test any(f -> f.metric == :cyclomatic && f.absolute == :ok && something(f.percentile, 0.0) >= 0.95, found)

    errs = Dendro.errors(dir)
    @test any(f -> f.metric == :nesting_depth && f.absolute == :high, errs)
    @test !any(f -> f.metric == :parameter_count, errs)
    @test !any(f -> f.metric == :cyclomatic, errs)
    @test Base.all(f -> f.absolute == :high, errs)
end

@testitem "quality gate: floor equals the high-band filter" tags = [:gate] begin
    using Dendro

    srcdir = joinpath(pkgdir(Dendro), "src")
    key(f) = (f.metric, f.value, sort([(loc.file, loc.line, loc.unit) for loc in f.locations]))
    keyset(fs) = Set(key(f) for f in fs)

    errs = Dendro.errors(srcdir)
    hand = filter(f -> f.absolute == :high, Dendro.active(Dendro.analyze(srcdir)))
    @test keyset(errs) == keyset(hand)
end
