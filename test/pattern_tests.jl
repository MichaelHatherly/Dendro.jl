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

@testitem "a fixture comment about the marker is not a marker" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    # A fixture explaining itself names its own rules, and a marker is read from the start
    # of a comment for the reason a `dendro-ignore` is: prose about the mechanism would
    # otherwise expect a match on the line under it.
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        # This file marks a line with `dendro-expect: loop_rule` where the rule must fire.
        function ok(x)
            while x    # dendro-expect: loop_rule
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

@testitem "fixtures can live apart from the queries" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(pdir)
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")

    elsewhere = joinpath(root, "fixtures")
    mkpath(joinpath(elsewhere, "tests"))
    # Deliberately wrong, so a pass would mean the fixture was never read.
    write(
        joinpath(elsewhere, "tests", "julia.jl"), """
        function ok(x)
            while x
            end
            for i in x  # dendro-expect: loop_rule
            end
        end
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(check_patterns(srcdir))
            fails = check_patterns(srcdir; fixtures = [elsewhere])
            # The query still comes from the pattern dir; only the fixture moved.
            @test Set((f.line, f.kind) for f in fails) == Set([(2, :unexpected), (4, :missed)])
        end
    end
end

@testitem "a marker on its own line describes the line under it" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    # A rule whose match is itself a comment. A comment carries no trailing comment, so
    # the marker has nowhere to sit but the line above.
    write(joinpath(pdir, "julia.patterns.scm"), "((line_comment) @rule_of_dashes (#match? @rule_of_dashes \"^#-{4,}\$\"))\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.rule_of_dashes]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        # dendro-expect: rule_of_dashes
        #-----
        # a heading keeps its text
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(check_patterns(srcdir; fixtures = [pdir]))
        end
    end
end

@testitem "a trailing marker still describes its own line" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))
    write(joinpath(pdir, "julia.patterns.scm"), "(while_statement) @loop_rule\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.loop_rule]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        function ok(x)
            while x    # dendro-expect: loop_rule
                g()
            end
        end
        """
    )
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(check_patterns(srcdir; fixtures = [pdir]))
        end
    end
end

@testitem "the shipped fixtures pin the shipped queries" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    # Outside Dendro's own repo the pack is the whole cascade, so the six names the repo's
    # rules shadow are read against the shipped query instead. The dogfood item runs the
    # same fixtures with the shadowing in place, so one file pins both spellings and the
    # two cannot drift apart unnoticed.
    _, srcdir = Fixtures.gitrepo()
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            failures = check_patterns(srcdir; fixtures = [joinpath(pkgdir(Dendro), "test", "patterns")])
            isempty(failures) || foreach(f -> println(stdout, f), failures)
            @test isempty(failures)
        end
    end
end

@testitem "the shipped fixtures pin the shipped queries under CRLF" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    # A Windows checkout turns every line ending into CRLF, and a line comment's node keeps
    # the carriage return, so a regex anchored at `$` misses it unless it says so. Line
    # endings are the only difference from the item above.
    shipped = joinpath(pkgdir(Dendro), "test", "patterns")
    _, srcdir = Fixtures.gitrepo()
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")
    mktempdir() do dir
        fixtures = joinpath(dir, "patterns")
        cp(shipped, fixtures)
        for (root, _, files) in walkdir(joinpath(fixtures, "tests")), f in files
            path = joinpath(root, f)
            write(path, replace(read(path, String), "\n" => "\r\n"))
        end
        withenv("XDG_CONFIG_HOME" => joinpath(dir, "xdg")) do
            failures = check_patterns(srcdir; fixtures = [fixtures])
            isempty(failures) || foreach(f -> println(stdout, f), failures)
            @test isempty(failures)
        end
    end
end
