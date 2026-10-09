@testitem "a scalar pattern rule counts per unit" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        """
        (integer_literal) @magic_number
        ((integer_literal) @magic_number.not (#any-of? @magic_number.not "0" "1"))
        """
    )
    write(
        joinpath(root, ".dendro.toml"),
        "cut = 1.01\n[patterns.magic_number]\nmessage = \"unnamed literal\"\nkind = \"scalar\"\nband = [3, 5]\n"
    )
    # `busy` holds 0, 1, 7, 8, 9: three counted, since 0 and 1 are excluded.
    # `calm` holds only excluded literals, so it scores zero and stays silent.
    write(
        joinpath(srcdir, "f.jl"), """
        function busy(x)
            return x + 0 + 1 + 7 + 8 + 9
        end
        function calm(x)
            return x + 0 + 1
        end
        """
    )

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hits = filter(f -> f.metric === :magic_number, analyze(srcdir))
            hit = only(hits)
            @test hit.kind === :scalar
            @test hit.value == 3
            @test hit.absolute === :warn        # 3 reaches warn, below the high of 5
            @test only(hit.locations).unit == "busy"
        end
    end
end

@testitem "a scalar pattern rule stops at a nested callable" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: pattern_count

    src = """
    function outer(x)
        a = 7
        function inner(y)
            return y + 8 + 9
        end
        return a + inner(x)
    end
    """
    _, index = Fixtures.patternindex(:julia, src, "(integer_literal) @lit\n")

    units = Dict(Dendro.unit_name(u, index) => u for u in Dendro.units(index))
    # The closure's 8 and 9 belong to the closure, not to `outer`. Every built-in
    # scalar stops at a nested callable and a pattern scalar that did not would read
    # as a Dendro bug.
    @test pattern_count(units["outer"], index, :lit) == 1
    @test pattern_count(units["inner"], index, :lit) == 2
end

@testitem "a scalar pattern rule counts each unit kind separately" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: pattern_count, units

    # One unit of each kind the query produces: a run of top-level statements, a
    # definition, the closure inside it, a run inside a module body, and the run the
    # module breaks off. The 9 is excluded, so the closure keeps only its 4.
    src = """
    x = 1
    y = 2
    function outer(a)
        b = 3
        function inner(c)
            return c + 4 + 9
        end
        return b + inner(a)
    end
    module M
        q = 7
    end
    z = 5
    """
    query = """
    (integer_literal) @lit
    ((integer_literal) @lit.not (#eq? @lit.not "9"))
    """
    _, index = Fixtures.patternindex(:julia, src, query)

    byline = Dict(u.firstline => u for u in units(index))
    @test sort!(collect(keys(byline))) == [1, 3, 5, 11, 13]
    @test pattern_count(byline[1], index, :lit) == 2
    @test pattern_count(byline[3], index, :lit) == 1
    @test pattern_count(byline[5], index, :lit) == 1
    @test pattern_count(byline[11], index, :lit) == 1
    @test pattern_count(byline[13], index, :lit) == 1
end

@testitem "a scalar pattern rule counts a callable it matches under that callable" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: pattern_count

    src = """
    function outer(x)
        function inner(y)
            return y
        end
        return inner(x)
    end
    """
    _, index = Fixtures.patternindex(:julia, src, "(function_definition) @fn\n")

    units = Dict(Dendro.unit_name(u, index) => u for u in Dendro.units(index))
    # A unit is measured from its own node inwards, so a match on the definition
    # itself is that definition's. The nested one belongs to its own unit alone.
    @test pattern_count(units["outer"], index, :fn) == 1
    @test pattern_count(units["inner"], index, :fn) == 1
end

@testitem "a scalar pattern band is retunable through [bands]" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(joinpath(root, ".dendro", "patterns", "julia.patterns.scm"), "(integer_literal) @magic_number\n")
    # A pattern scalar is nameable under [bands] exactly as `cyclomatic` is, so a
    # project retunes its own rule the same way it retunes a built-in.
    write(
        joinpath(root, ".dendro.toml"),
        """
        cut = 1.01
        [patterns.magic_number]
        message = "unnamed literal"
        kind = "scalar"
        band = [50, 99]

        [bands]
        magic_number = [2, 3]
        """
    )
    write(joinpath(srcdir, "f.jl"), "function f(x)\n    return x + 1 + 2 + 3\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hit = only(filter(f -> f.metric === :magic_number, analyze(srcdir)))
            @test hit.value == 3
            @test hit.absolute === :high   # the override, not the declared [50, 99]
        end
    end
end

@testitem "a scalar pattern rule with no matches stays ok" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(joinpath(root, ".dendro", "patterns", "julia.patterns.scm"), "(while_statement) @loops\n")
    write(
        joinpath(root, ".dendro.toml"),
        "cut = 1.01\n[patterns.loops]\nmessage = \"m\"\nkind = \"scalar\"\nband = [1, 2]\n"
    )
    write(joinpath(srcdir, "f.jl"), "function f(x)\n    return x\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            # A band starting at 1 is what keeps `severity(0, band)` at `:ok`, so a unit
            # holding no matches cannot breach the absolute score.
            @test isempty(filter(f -> f.metric === :loops, analyze(srcdir)))
        end
    end
end
