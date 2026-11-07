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

# The ratchet (`errors(; since)`): the floor at the working tree minus the floor at a
# base ref. A finding the change introduced is reported; one that predates the ref, even
# on a touched line, is not. Each item builds a throwaway git repo at runtime.

@testitem "quality gate: ratchet reports a new violation" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    root, src = Fixtures.gitrepo()
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["clean(1)"], "clean(c) = c + 1\n"))
    Fixtures.commit!(root, "clean base")
    # The working tree adds an over-band function, referenced so only its nesting trips.
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["clean(1)", "big(0)"], "clean(c) = c + 1\n" * Fixtures.deepfn("big")))

    errs = Dendro.errors(src; since = "HEAD")
    @test length(errs) == 1
    @test errs[1].metric == :nesting_depth
    @test first(errs[1].locations).unit == "big"
end

@testitem "quality gate: ratchet ignores a touched but unworsened violation" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    root, src = Fixtures.gitrepo()
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["big(0)"], Fixtures.deepfn("big")))
    Fixtures.commit!(root, "already over band")
    # Touch an unrelated line in the file; `big`'s nesting is unchanged.
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["big(0)", "helper()"], Fixtures.deepfn("big") * "helper() = 0\n"))

    # The pre-existing violation is in the working-tree floor, so a non-empty floor and an
    # empty ratchet together prove the base finding matched (a realpath/relpath regression
    # would leave it unmatched and re-report it).
    @test !isempty(Dendro.errors(src))
    @test isempty(Dendro.errors(src; since = "HEAD"))
end

@testitem "quality gate: ratchet counts multiplicity" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    root, src = Fixtures.gitrepo()
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["f(0)"], Fixtures.catchfn("f", 1)))
    Fixtures.commit!(root, "one empty catch")
    # A second empty catch in the same file: same key, one more occurrence.
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["f(0)"], Fixtures.catchfn("f", 2)))

    errs = Dendro.errors(src; since = "HEAD")
    @test length(errs) == 1
    @test errs[1].metric == :empty_catch
end

@testitem "quality gate: ratchet matches an edited clone, flags a third copy" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    # Base: an exact clone pair.
    root, src = Fixtures.gitrepo()
    pair = Fixtures.chain("alpha", 6) * Fixtures.chain("beta", 6)
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["alpha(0)", "beta(0)"], pair))
    Fixtures.commit!(root, "clone pair")

    # Editing one copy's body breaks the clone, introducing nothing new.
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["alpha(0)", "beta(0)"], Fixtures.chain("alpha", 6) * Fixtures.chain("beta", 5)))
    @test isempty(Dendro.errors(src; since = "HEAD"))

    # A third copy grows the clone to a triple, a new finding.
    triple = pair * Fixtures.chain("gamma", 6)
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["alpha(0)", "beta(0)", "gamma(0)"], triple))
    errs = Dendro.errors(src; since = "HEAD")
    @test length(errs) == 1
    @test errs[1].metric == :duplicate
end

@testitem "quality gate: ratchet matches a clone that lost a copy" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    # Base: an exact clone triple, one finding over three sites.
    root, src = Fixtures.gitrepo()
    pair = Fixtures.chain("alpha", 6) * Fixtures.chain("beta", 6)
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["alpha(0)", "beta(0)", "gamma(0)"], pair * Fixtures.chain("gamma", 6)))
    Fixtures.commit!(root, "clone triple")

    # Deleting one copy leaves a pair the triple already reported, so nothing is new.
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["alpha(0)", "beta(0)"], pair))
    @test !isempty(Dendro.errors(src))
    @test isempty(Dendro.errors(src; since = "HEAD"))
end

@testitem "quality gate: ratchet matches a file-level finding whose count fell" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    # `:low_cohesion` is about the file, and its locations are one representative per
    # component. Base: four components, `f1` representing the one it shares with `g1`.
    root, src = Fixtures.gitrepo()
    write(joinpath(root, ".dendro.toml"), "[bands]\nlow_cohesion = [2, 3]\n")
    write(joinpath(src, "mod.jl"), "include(\"m.jl\")\ninclude(\"other.jl\")\n")
    write(joinpath(src, "m.jl"), "f1() = g1()\ng1() = 1\nh() = 2\nk() = 3\np() = 4\n")
    write(joinpath(src, "other.jl"), "z() = 0\n")
    Fixtures.commit!(root, "four components")

    cohesion(fs) = filter(f -> f.metric === :low_cohesion, fs)
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            # Moving `f1` and `p` out leaves three components and makes `g1` a
            # representative. The count fell, so the gate has nothing new to report.
            write(joinpath(src, "m.jl"), "g1() = 1\nh() = 2\nk() = 3\n")
            write(joinpath(src, "other.jl"), "z() = f1() + p()\nf1() = g1()\np() = 4\n")
            @test length(cohesion(Dendro.errors(src))) == 1
            @test isempty(cohesion(Dendro.errors(src; since = "HEAD")))

            # A fifth component raises the count over the base, which is worsening.
            write(joinpath(src, "m.jl"), "f1() = g1()\ng1() = 1\nh() = 2\nk() = 3\np() = 4\nq() = 5\n")
            write(joinpath(src, "other.jl"), "z() = 0\n")
            @test length(cohesion(Dendro.errors(src; since = "HEAD"))) == 1
        end
    end
end

@testitem "quality gate: ratchet identifies a finding by its home" tags = [:gate] begin
    using Dendro

    mktempdir() do root
        for name in ("a.jl", "b.jl", "c.jl")
            touch(joinpath(root, name))
        end
        at(file, unit) = Dendro.Location(joinpath(root, file), 1, unit)
        finding(metric, value, locations...) = Dendro.Finding(metric, collect(locations), value, :high, nothing, :scalar, false)
        new(head, base) = length(Dendro.ratchet(Dendro.Findings(head), Dendro.floor_keys(Dendro.Findings(base), root), root))

        # A file-level finding is the file: another representative at the same value is the
        # same finding, a higher value is worsening.
        hub = finding(:hub, 3, at("a.jl", ""), at("a.jl", "x"), at("a.jl", "y"))
        @test new([finding(:hub, 3, at("a.jl", ""), at("a.jl", "z"))], [hub]) == 0
        @test new([finding(:hub, 4, at("a.jl", ""), at("a.jl", "x"), at("a.jl", "y"))], [hub]) == 1
        @test new([finding(:hub, 3, at("b.jl", ""))], [hub]) == 1

        # A finding about one unit is that unit, whatever it points at.
        envy = finding(:misplaced, 80, at("a.jl", "f"), at("b.jl", ""))
        @test new([finding(:misplaced, 70, at("a.jl", "f"), at("c.jl", ""))], [envy]) == 0
        @test new([finding(:misplaced, 90, at("a.jl", "f"), at("b.jl", ""))], [envy]) == 1

        # A finding whose sites are the edit keeps its exact site set, so one more site is new.
        edge = finding(:back_edge, 90, at("a.jl", ""), at("a.jl", "f"))
        @test new([edge], [edge]) == 0
        @test new([finding(:back_edge, 90, at("a.jl", ""), at("a.jl", "f"), at("a.jl", "g"))], [edge]) == 1
    end
end

@testitem "quality gate: ratchet treats paths absent at base as all-new" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    root, src = Fixtures.gitrepo()
    # Commit a repo without `src/`; the archive of `src` at HEAD matches nothing.
    rm(src; recursive = true)
    write(joinpath(root, "README.md"), "base\n")
    Fixtures.commit!(root, "no src yet")

    mkpath(src)
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["big(0)"], Fixtures.deepfn("big")))
    errs = Dendro.errors(src; since = "HEAD")
    @test any(f -> f.metric == :nesting_depth && first(f.locations).unit == "big", errs)
end

@testitem "quality gate: ratchet throws on an unknown since ref" tags = [:gate] setup = [Fixtures] begin
    using Dendro

    root, src = Fixtures.gitrepo()
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["big(0)"], Fixtures.deepfn("big")))
    Fixtures.commit!(root, "base")

    @test_throws "Dendro: `since` ref not found" Dendro.errors(src; since = "no-such-ref")
end

@testitem "quality gate honors a repo .dendro.toml" tags = [:gate] setup = [Fixtures] begin
    using Dendro: errors

    # A referenced flat function whose cyclomatic count sits under the default bands, so the
    # floor is empty until the repo file tightens the band. `modsrc` calls `f`, so the
    # unreferenced pass stays quiet and cyclomatic is the only band in play. The gate
    # resolves the same config as `analyze`, so the retune reaches it. The global layer is
    # isolated so a developer's own config cannot flag the function first.
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "m.jl"), Fixtures.modsrc(["f(1)"], Fixtures.guards("f", 6)))

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(errors(src))   # default bands leave the floor empty

            write(joinpath(root, ".dendro.toml"), "[bands]\ncyclomatic = [1, 2]\n")
            flagged = errors(src)
            @test !isempty(flagged)
            @test any(f -> f.metric === :cyclomatic, flagged)
        end
    end
end
