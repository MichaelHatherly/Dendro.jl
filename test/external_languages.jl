@testitem "external language registers from a config file" setup = [Fixtures] tags = [:external] begin
    using Dendro: discover_config, language_for_path, extension_map, resolve_profiles, PROFILES

    mktempdir() do dir
        qdir = joinpath(dir, "queries")
        mkpath(qdir)
        cp(joinpath(pkgdir(Dendro), "src", "queries", "python.scm"), joinpath(qdir, "mylang.scm"))
        f = joinpath(dir, "c.toml")
        write(
            f, """
            [languages.mylang]
            extensions = ["mypy"]
            grammar = "python"
            queries = "$(escape_string(qdir))"
            """
        )
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = f)
            end
        end

        profiles = resolve_profiles(cfg)
        @test profiles[:mylang].grammar == "python"
        @test profiles[:mylang].queries == qdir

        # The configured extension resolves against the registry, the built-ins still do.
        exts = extension_map(profiles)
        @test language_for_path("a.mypy", exts) === :mylang
        @test language_for_path("a.jl", exts) === :julia
        # The built-in registry does not know the extension, so nothing leaked into it.
        @test language_for_path("a.mypy", extension_map(PROFILES)) === nothing
    end
end

@testitem "external language scores a file end to end" setup = [Fixtures] tags = [:external] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        qdir = joinpath(dir, "queries")
        mkpath(qdir)
        cp(joinpath(pkgdir(Dendro), "src", "queries", "python.scm"), joinpath(qdir, "mylang.scm"))
        cfgfile = joinpath(dir, "c.toml")
        write(
            cfgfile, """
            cut = 1.01
            [bands]
            cyclomatic = [3, 4]
            [languages.mylang]
            extensions = ["mypy"]
            grammar = "python"
            queries = "$(escape_string(qdir))"
            """
        )
        src = joinpath(dir, "src")
        mkpath(src)
        write(joinpath(src, "f.mypy"), Fixtures.py_guards("f", 6))

        found = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                analyze(src; config = discover_config([src]; explicit = cfgfile))
            end
        end
        hit = only(filter(f -> f.metric === :cyclomatic, found))
        @test hit.absolute === :high
        @test hit.locations[1].unit == "f"
    end
end

@testitem "external language grammar loads from a local repo directory" setup = [Fixtures] tags = [:external] begin
    using Dendro: LanguageProfile, language_grammar

    # A directory grammar takes the local-repo branch, which needs a tree-sitter.json.
    # Asserting that error proves the branch was taken without shipping a built grammar.
    mktempdir() do dir
        @test_throws "No tree-sitter.json" language_grammar(LanguageProfile(:mylang, dir, dir))
    end

    # A grammar name that is not a directory takes the JLL branch.
    @test_throws "no parser for language" language_grammar(LanguageProfile(:nope, "nope", "nope"))
end

@testitem "external language config rejects a malformed table" setup = [Fixtures] tags = [:external] begin
    using Dendro: discover_config, ConfigError

    mktempdir() do dir
        bare = joinpath(dir, "bare.toml")
        write(bare, "[languages.mylang]\nextensions = [\"mypy\"]\n")
        @test_throws ConfigError mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = bare)
            end
        end

        bad = joinpath(dir, "bad.toml")
        write(bad, "[languages.mylang]\nextensions = [1]\ngrammar = \"python\"\nqueries = \"q\"\n")
        @test_throws ConfigError mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = bad)
            end
        end
    end
end

@testitem "external language config warns on an unknown key" setup = [Fixtures] tags = [:external] begin
    using Dendro: discover_config, resolve_profiles

    mktempdir() do dir
        odd = joinpath(dir, "odd.toml")
        write(odd, "[languages.mylang]\nextensions = [\"mypy\"]\ngrammar = \"python\"\nqueries = \"q\"\nbogus = 1\n")
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                @test_logs (:warn,) match_mode = :any discover_config([dir]; explicit = odd)
            end
        end
        # The unknown key warned and was dropped; the language still registered.
        @test haskey(resolve_profiles(cfg), :mylang)
    end
end

@testitem "external language overrides a built-in of the same name" setup = [Fixtures] tags = [:external] begin
    using Dendro: discover_config, resolve_profiles, PROFILES

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(f, "[languages.python]\nextensions = [\"py\"]\ngrammar = \"/nonexistent\"\nqueries = \"q\"\n")
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = f)
            end
        end
        @test resolve_profiles(cfg)[:python].grammar == "/nonexistent"
        # The built-in table is untouched, so one analysis cannot leak into the next.
        @test PROFILES[:python].grammar == "python"
    end
end

@testitem "external language caches keyed by its queries" setup = [Fixtures] tags = [:external] begin
    using Dendro: LanguageProfile, query_for

    # Two profiles sharing a name but reading different queries must not share a cache
    # entry, or a second project's :mylang would score against the first project's query.
    mktempdir() do dir
        one = joinpath(dir, "one")
        two = joinpath(dir, "two")
        mkpath(one)
        mkpath(two)
        cp(joinpath(pkgdir(Dendro), "src", "queries", "python.scm"), joinpath(one, "mylang.scm"))
        write(joinpath(two, "mylang.scm"), "(function_definition) @function\n")

        a = query_for(LanguageProfile(:mylang, "python", one))
        b = query_for(LanguageProfile(:mylang, "python", two))
        @test a !== b
        @test query_for(LanguageProfile(:mylang, "python", one)) === a
    end
end
