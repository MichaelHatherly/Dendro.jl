@testitem ":split_audience flags a file serving two disjoint audiences" setup = [Fixtures] tags = [:split_audience] begin
    # f.jl's `fa`/`fb` are read only by x.jl and its `fc`/`fd` only by y.jl: two consumer
    # sets that never meet, so the file splits cleanly in two.
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, "fa() = 1\nfb() = 2\nfc() = 3\nfd() = 4\n"; file = "f.jl")
    x = Fixtures.parsedfile(:julia, "x1() = fa() + fb()\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "y1() = fc() + fd()\n"; file = "y.jl")
    files = [mod, f, x, y]
    table = Dendro.corpus_symbols(files)
    findings = Dendro.cluster_split_audience(files, table; band = (2, 3))

    hit = only(findings)
    @test hit.metric == :split_audience
    @test hit.kind == :scalar
    @test hit.value == 2
    @test hit.absolute == :warn
    # Four files, so the percentile gate stays off: only the absolute band fires.
    @test hit.percentile === nothing
    # One representative definition per audience group, earliest line first.
    @test [(l.file, l.unit, l.line) for l in hit.locations] == [("f.jl", "fa", 1), ("f.jl", "fc", 3)]
end

@testitem ":split_audience merges groups a shared definition joins" setup = [Fixtures] tags = [:split_audience] begin
    # `fe` is read by both consumers, so its consumer set meets both others and the two
    # audiences become one: the file has nothing to split along.
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, "fa() = 1\nfb() = 2\nfc() = 3\nfd() = 4\nfe() = 5\n"; file = "f.jl")
    x = Fixtures.parsedfile(:julia, "x1() = fa() + fb() + fe()\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "y1() = fc() + fd() + fe()\n"; file = "y.jl")
    files = [mod, f, x, y]
    table = Dendro.corpus_symbols(files)
    hit = only(Dendro.cluster_split_audience(files, table; band = (1, 2)))

    @test hit.value == 1
    @test [(l.unit, l.line) for l in hit.locations] == [("fa", 1)]
end

@testitem ":split_audience reads a language with no export marker the same way" setup = [Fixtures] tags = [:split_audience] begin
    # Python declares no exports, so the audience is resolved from references alone,
    # exactly as it is for Julia's splice linkage. Same shape, same verdict.
    f = Fixtures.parsedfile(:python, "def fa():\n    return 1\ndef fb():\n    return 2\ndef fc():\n    return 3\ndef fd():\n    return 4\n"; file = "f.py")
    x = Fixtures.parsedfile(:python, "from f import fa, fb\ndef x1():\n    return fa() + fb()\n"; file = "x.py")
    y = Fixtures.parsedfile(:python, "from f import fc, fd\ndef y1():\n    return fc() + fd()\n"; file = "y.py")
    files = [f, x, y]
    table = Dendro.corpus_symbols(files)
    hit = only(Dendro.cluster_split_audience(files, table; band = (2, 3)))

    @test hit.value == 2
    @test [(l.file, l.unit, l.line) for l in hit.locations] == [("f.py", "fa", 1), ("f.py", "fc", 5)]
end

@testitem ":split_audience leaves a file with one audience alone" setup = [Fixtures] tags = [:split_audience] begin
    # One consumer file reads everything f.jl offers: one audience, nothing to split.
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, "fa() = 1\nfb() = 2\nfc() = 3\nfd() = 4\n"; file = "f.jl")
    x = Fixtures.parsedfile(:julia, "x1() = fa() + fb()\nx2() = fc() + fd()\n"; file = "x.jl")
    files = [mod, f, x]
    table = Dendro.corpus_symbols(files)
    @test isempty(Dendro.cluster_split_audience(files, table; band = (1, 2)))
end

@testitem ":split_audience skips a file below the unit floor" setup = [Fixtures] tags = [:split_audience] begin
    # Two definitions serving two audiences is too small a file to read as split.
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, "fa() = 1\nfb() = 2\n"; file = "f.jl")
    x = Fixtures.parsedfile(:julia, "x1() = fa()\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "y1() = fb()\n"; file = "y.jl")
    files = [mod, f, x, y]
    table = Dendro.corpus_symbols(files)
    @test isempty(Dendro.cluster_split_audience(files, table; band = (1, 2)))
end

@testitem ":split_audience needs two definitions per group" setup = [Fixtures] tags = [:split_audience] begin
    # Each consumer reads one definition: two groups, but both singletons, which is the
    # ordinary shape of a helper with a single caller rather than an audience.
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, "fa() = 1\nfb() = 2\nfc() = 3\n"; file = "f.jl")
    x = Fixtures.parsedfile(:julia, "x1() = fa()\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "y1() = fb()\n"; file = "y.jl")
    files = [mod, f, x, y]
    table = Dendro.corpus_symbols(files)
    @test isempty(Dendro.cluster_split_audience(files, table; band = (1, 2)))
end

@testitem ":split_audience respects dendro-ignore-file" setup = [Fixtures] tags = [:split_audience] begin
    fsrc = "# dendro-ignore-file: split_audience\nfa() = 1\nfb() = 2\nfc() = 3\nfd() = 4\n"
    i = Fixtures.idx(:julia, fsrc)
    directives = Dendro.suppressions(i; file = "f.jl")
    mod = Fixtures.parsedfile(:julia, "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n"; file = "mod.jl")
    f = Fixtures.parsedfile(:julia, fsrc; file = "f.jl", directives = directives)
    x = Fixtures.parsedfile(:julia, "x1() = fa() + fb()\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "y1() = fc() + fd()\n"; file = "y.jl")
    files = [mod, f, x, y]
    table = Dendro.corpus_symbols(files)
    hit = only(Dendro.cluster_split_audience(files, table; band = (2, 3)))
    @test hit.suppressed
end

@testitem ":split_audience reaches analyze through the config band" setup = [Fixtures] tags = [:split_audience] begin
    mktempdir() do dir
        write(joinpath(dir, "mod.jl"), "include(\"f.jl\")\ninclude(\"x.jl\")\ninclude(\"y.jl\")\n")
        write(joinpath(dir, "f.jl"), "fa() = 1\nfb() = 2\nfc() = 3\nfd() = 4\n")
        write(joinpath(dir, "x.jl"), "x1() = fa() + fb()\n")
        write(joinpath(dir, "y.jl"), "y1() = fc() + fd()\n")
        toml = joinpath(dir, "c.toml")
        write(toml, "[bands]\nsplit_audience = [2, 3]\n")

        # Isolate the user-global layer so a developer's own config cannot leak in.
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                Dendro.discover_config([dir]; explicit = toml)
            end
        end
        @test cfg.split_audience == (2, 3)
        hit = only(filter(f -> f.metric == :split_audience, Dendro.analyze(dir; config = cfg)))
        @test hit.value == 2
        @test basename(first(hit.locations).file) == "f.jl"
    end
end
