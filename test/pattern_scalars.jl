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
    index = Fixtures.idx(:julia, src)
    tree = Dendro.TreeSitter.parse(Dendro.parser_for(:julia), src)
    g = Dendro.language_grammar(Dendro.PROFILES[:julia])
    q = Dendro.compile_pattern_query(g, "(integer_literal) @lit\n", "julia.patterns.scm")
    Dendro.index_patterns!(index, tree, q, src)

    units = Dict(Dendro.unit_name(u, index) => u for u in Dendro.functions(index))
    # The closure's 8 and 9 belong to the closure, not to `outer`. Every built-in
    # scalar stops at a nested callable and a pattern scalar that did not would read
    # as a Dendro bug.
    @test pattern_count(units["outer"], index, :lit) == 1
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
