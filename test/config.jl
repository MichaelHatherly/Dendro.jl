@testitem "config defaults match the built-in rules" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config, resolve_rules, BUILTIN_RULES

    mktempdir() do dir
        cfg = discover_config([dir]; use_files = false)
        @test cfg.cut == 0.95
        @test isempty(cfg.bands)
        @test isempty(cfg.rules)
        @test [r.name for r in resolve_rules(cfg)] == [r.name for r in BUILTIN_RULES]
    end
end

@testitem "config band override flags via the absolute band" setup = [Fixtures] tags = [:config] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        write(joinpath(dir, "f.jl"), Fixtures.guards("f", 6))

        # cut above 1 disables percentile scoring, isolating the absolute band.
        base = discover_config([dir]; use_files = false)
        @test isempty(filter(f -> f.metric === :cyclomatic, analyze(dir; config = base, cut = 1.01)))

        tight = discover_config([dir]; use_files = false)
        tight.bands[:cyclomatic] = (3, 4)
        hit = only(filter(f -> f.metric === :cyclomatic, analyze(dir; config = tight, cut = 1.01)))
        @test hit.absolute === :high
    end
end

@testitem "config discovers a repo .dendro.toml" setup = [Fixtures] tags = [:config] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    write(joinpath(srcdir, "f.jl"), Fixtures.guards("f", 6))
    write(joinpath(root, ".dendro.toml"), "cut = 1.01\n[bands]\ncyclomatic = [3, 4]\n")

    # Isolate the user-global layer so a developer's own config cannot leak in.
    hit = mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            only(filter(f -> f.metric === :cyclomatic, analyze(srcdir)))
        end
    end
    @test hit.absolute === :high
end

@testitem "config coerces values and drops unknown bands" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(f, "cut = 1\n[bands]\nlow_cohesion = [5, 7]\nbogus = [1, 2]\n")
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                @test_logs (:warn,) match_mode = :any discover_config([dir]; explicit = f)
            end
        end
        @test cfg.cut == 1.0              # an integer cut coerces to Float64
        @test cfg.low_cohesion == (5, 7)  # a relational band reaches its field
        @test isempty(cfg.bands)          # the unknown `bogus` warned and was dropped
    end
end

@testitem "config sets clone-detection thresholds" setup = [Fixtures] tags = [:config] begin
    using Dendro: analyze

    # Two renamed clones caught at the default min_size; a raised floor suppresses them.
    # Both analyses run under an isolated global layer.
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
        mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                @test !isempty(filter(f -> f.metric === :duplicate, analyze(dir)))
                write(joinpath(dir, ".dendro.toml"), "[clones]\nmin_size = 1000\n")
                @test isempty(filter(f -> f.metric === :duplicate, analyze(dir)))
            end
        end
    end
end

@testitem "config toggles optional and built-in rules" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config, resolve_rules

    mktempdir() do dir
        cfg = discover_config([dir]; use_files = false)
        cfg.rules[:npath] = true
        cfg.rules[:parameter_count] = false
        names = Set(r.name for r in resolve_rules(cfg))
        @test :npath in names
        @test !(:parameter_count in names)
    end
end

@testitem "explicit kwargs beat the config" setup = [Fixtures] tags = [:config] begin
    using Dendro: analyze, discover_config, BUILTIN_RULES

    mktempdir() do dir
        write(joinpath(dir, "f.jl"), Fixtures.guards("f", 6))

        cfg = discover_config([dir]; use_files = false)
        cfg.rules[:cyclomatic] = false
        @test isempty(filter(f -> f.metric === :cyclomatic, analyze(dir; config = cfg, cut = 1.01)))

        # An explicit rule set restores the metric and an explicit cut beats the
        # config's, so the lone function's percentile flags it again.
        restored = analyze(dir; config = cfg, rules = BUILTIN_RULES, cut = 0.5)
        @test !isempty(filter(f -> f.metric === :cyclomatic, restored))
    end
end

@testitem "global config underlies the repo file" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config

    mktempdir() do xdg
        gdir = joinpath(xdg, "dendro")
        mkpath(gdir)
        write(joinpath(gdir, "config.toml"), "cut = 0.5\n[bands]\ncyclomatic = [1, 2]\n")
        root, srcdir = Fixtures.gitrepo()
        write(joinpath(root, ".dendro.toml"), "cut = 0.9\n[bands]\nfunction_length = [1, 2]\n")

        cfg = withenv("XDG_CONFIG_HOME" => xdg) do
            discover_config([srcdir])
        end
        @test cfg.cut == 0.9                          # repo file wins
        @test cfg.bands[:cyclomatic] == (1, 2)        # carried from the global file
        @test cfg.bands[:function_length] == (1, 2)   # set by the repo file
    end
end

@testitem "config warns on unknown keys" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(f, "wat = 1\n[bands]\ncyclomatik = [1, 2]\n[rules]\nnope = true\n")
        @test_logs (:warn,) (:warn,) (:warn,) match_mode = :any discover_config([dir]; explicit = f)
    end
end

@testitem "reimplementation config keys" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config

    # The global layer is isolated so a developer's own config cannot add logs.
    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                write(f, "[reimplementation]\nthreshold = 0.7\n")
                cfg = discover_config([dir]; explicit = f)
                @test cfg.reimpl_threshold == 0.7

                # The corpus-pass toggle validates under [rules] without a
                # warning, though no Rule carries the name.
                write(f, "[rules]\nreimplementation = true\n")
                cfg = @test_logs discover_config([dir]; explicit = f)
                @test cfg.rules[:reimplementation] === true

                # An unknown key under the table warns and is dropped.
                write(f, "[reimplementation]\nthresh = 0.7\n")
                cfg = @test_logs (:warn,) discover_config([dir]; explicit = f)
                @test cfg.reimpl_threshold == Dendro.DEFAULT_REIMPL_THRESHOLD
            end
        end
    end
end

@testitem "config errors on a missing explicit file" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config, ConfigError

    mktempdir() do dir
        @test_throws ConfigError discover_config([dir]; explicit = joinpath(dir, "nope.toml"))
    end
end

@testitem "config rejects malformed values with a clean error" setup = [Fixtures] tags = [:config] begin
    using Dendro: discover_config, ConfigError

    # Each value parses as TOML but is the wrong shape for its field. The loader throws a
    # `ConfigError`, not a bare coercion failure, so the CLI reports it cleanly. The
    # global layer is isolated so a developer's own config cannot satisfy the key first.
    cases = [
        ("[bands]\ncyclomatic = [5]\n", "two integers"),       # band needs two entries
        ("[bands]\ncyclomatic = 5\n", "two integers"),         # band is not an array
        ("cut = \"x\"\n", "must be a number"),                 # cut is not numeric
        ("[rules]\nnpath = \"yes\"\n", "true or false"),       # toggle is not a boolean
        ("[clones]\nmin_size = 1.5\n", "must be an integer"),  # min_size is not integral
        ("[reimplementation]\nthreshold = \"x\"\n", "must be a number"),
        ("bands = 5\n", "must be a table"),                    # section is not a table
    ]
    for (toml, frag) in cases
        mktempdir() do dir
            f = joinpath(dir, "c.toml")
            write(f, toml)
            mktempdir() do xdg
                withenv("XDG_CONFIG_HOME" => xdg) do
                    err = try
                        discover_config([dir]; explicit = f)
                        nothing
                    catch e
                        e
                    end
                    @test err isa ConfigError
                    @test occursin(frag, err.msg)
                end
            end
        end
    end
end
