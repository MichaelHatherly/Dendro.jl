@testitem "pattern declarations parse into specs" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: discover_config

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(
            f, """
            [patterns.no_any]
            message = "`::Any` defeats dispatch"

            [patterns.empty_catch_binding]
            message  = "catch with no binding"
            severity = "high"

            [patterns.magic_number]
            message = "unnamed numeric literal"
            kind    = "scalar"
            band    = [3, 6]
            """
        )
        cfg = Fixtures.isolated_config(dir, f)
        specs = Dict(s.name => s for s in cfg.patterns)

        @test length(cfg.patterns) == 3
        # Sorted by name, so a report reads in a stable order.
        @test [s.name for s in cfg.patterns] == [:empty_catch_binding, :magic_number, :no_any]

        @test specs[:no_any].message == "`::Any` defeats dispatch"
        @test specs[:no_any].severity === :warn   # the default keeps a new rule out of the gate
        @test specs[:no_any].kind === :flag
        @test specs[:no_any].band === nothing

        @test specs[:empty_catch_binding].severity === :high
        @test specs[:magic_number].kind === :scalar
        @test specs[:magic_number].band == (3, 6)
    end
end

@testitem "pattern declarations reject malformed tables" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError

    bad = [
        # A missing message: the finding would have nothing to say.
        ("[patterns.a]\n", "message"),
        # A value the author clearly meant to set, so an error rather than a warning.
        ("[patterns.a]\nmessage = \"m\"\nseverity = \"critical\"\n", "severity"),
        ("[patterns.a]\nmessage = \"m\"\nkind = \"vector\"\n", "kind"),
        # A flag carries no band; a scalar cannot go without one.
        ("[patterns.a]\nmessage = \"m\"\nband = [1, 2]\n", "band"),
        ("[patterns.a]\nmessage = \"m\"\nkind = \"scalar\"\n", "band"),
        # ADR line 50: a band starting below 1 lets a unit with no matches score.
        ("[patterns.a]\nmessage = \"m\"\nkind = \"scalar\"\nband = [0, 2]\n", "1"),
    ]
    for (toml, needle) in bad
        mktempdir() do dir
            f = joinpath(dir, "c.toml")
            write(f, toml)
            err = try
                Fixtures.isolated_config(dir, f)
                nothing
            catch e
                e
            end
            @test err isa ConfigError
            @test occursin(needle, err.msg)
        end
    end
end

@testitem "pattern declarations warn on an unknown key" setup = [Fixtures] tags = [:patterns] begin
    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(f, "[patterns.a]\nmessage = \"m\"\nnonsense = 1\n")
        cfg = @test_logs (:warn,) match_mode = :any Fixtures.isolated_config(dir, f)
        # Warned and dropped, as an unknown band does: the rule still loads.
        @test only(cfg.patterns).name === :a
    end
end
