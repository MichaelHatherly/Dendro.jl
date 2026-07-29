@testitem "a fixture pins what a rule must and must not match" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")

    # Every `while` is marked and nothing else is, so the rule and the fixture agree.
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        function ok(x)
            while x    # dendro-expect: loop_rule
                g()
            end
            for i in x
            end
        end
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(check_patterns(srcdir))
        end
    end
end

@testitem "a fixture catches a false positive" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    # Too broad: catches every loop, where the fixture says only `while` was wanted.
    write(joinpath(pdir, "julia.patterns.scm"), "[(while_statement) (for_statement)] @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        function ok(x)
            while x    # dendro-expect: loop_rule
            end
            for i in x
            end
        end
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            fails = check_patterns(srcdir)
            # The unmarked `for` fired. Only checking that a rule matched something would
            # have passed this, which is why the unexpected direction is the point.
            f = only(fails)
            @test f.kind === :unexpected
            @test f.rule === :loop_rule
            @test f.line == 4
        end
    end
end

@testitem "a fixture catches a missed expectation" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    # Too narrow: the fixture expects both loops, the rule finds only `while`.
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        function ok(x)
            while x    # dendro-expect: loop_rule
            end
            for i in x # dendro-expect: loop_rule
            end
        end
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            f = only(check_patterns(srcdir))
            @test f.kind === :missed
            @test f.line == 4
        end
    end
end

@testitem "a rule with no fixture is not a failure" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(pdir)
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            # Requiring one would be friction on a two-line house rule, and the
            # zero-match report already covers the rule that never fires.
            @test isempty(check_patterns(srcdir))
        end
    end
end
