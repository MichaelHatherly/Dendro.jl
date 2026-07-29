@testitem ":incoherent_package flags a directory whose files each belong elsewhere" setup = [Fixtures] tags = [:incoherent_package] begin
    # Each of pkg/'s three units couples to a different other directory, so every one of
    # them lands in a community anchored outside pkg/: the layout disagrees with the
    # coupling for the whole directory.
    mod = Fixtures.parsedfile(
        :julia,
        "include(\"pkg/one.jl\")\ninclude(\"pkg/two.jl\")\ninclude(\"pkg/three.jl\")\n" *
            "include(\"a/a.jl\")\ninclude(\"b/b.jl\")\ninclude(\"c/c.jl\")\n";
        file = "mod.jl"
    )
    one = Fixtures.parsedfile(:julia, "p1() = ay() + az()\n"; file = "pkg/one.jl")
    two = Fixtures.parsedfile(:julia, "p2() = by() + bz()\n"; file = "pkg/two.jl")
    three = Fixtures.parsedfile(:julia, "p3() = cy() + cz()\n"; file = "pkg/three.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a/a.jl")
    b = Fixtures.parsedfile(:julia, "by() = bz()\nbz() = by()\n"; file = "b/b.jl")
    c = Fixtures.parsedfile(:julia, "cy() = cz()\ncz() = cy()\n"; file = "c/c.jl")
    files = [mod, one, two, three, a, b, c]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    findings = Dendro.cluster_incoherent_packages(files, graph)

    f = only(findings)
    @test f.metric == :incoherent_package
    @test f.kind == :scalar
    # All three units belong elsewhere.
    @test f.value == 100
    @test f.absolute == :high
    # Fewer directories than the percentile floor, so only the absolute band fires.
    @test f.percentile === nothing
    # A source unit then the target it belongs with, one pair per elsewhere-anchored
    # community, the pairs in path then line order. The target locations are what name
    # the directories.
    @test [(l.file, l.unit) for l in f.locations] == [
        ("pkg/one.jl", "p1"), ("a/a.jl", "ay"),
        ("pkg/three.jl", "p3"), ("c/c.jl", "cy"),
        ("pkg/two.jl", "p2"), ("b/b.jl", "by"),
    ]
end

@testitem ":incoherent_package leaves a cohesive directory alone" setup = [Fixtures] tags = [:incoherent_package] begin
    # pkg/'s units reference each other across its files, so they settle into one
    # community anchored in pkg/ despite the single call out to a/.
    mod = Fixtures.parsedfile(
        :julia,
        "include(\"pkg/one.jl\")\ninclude(\"pkg/two.jl\")\ninclude(\"pkg/three.jl\")\ninclude(\"a/a.jl\")\n";
        file = "mod.jl"
    )
    one = Fixtures.parsedfile(:julia, "p1() = p2() + p3()\n"; file = "pkg/one.jl")
    two = Fixtures.parsedfile(:julia, "p2() = p3() + ay()\n"; file = "pkg/two.jl")
    three = Fixtures.parsedfile(:julia, "p3() = p1()\n"; file = "pkg/three.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a/a.jl")
    files = [mod, one, two, three, a]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    @test isempty(Dendro.cluster_incoherent_packages(files, graph))
end

@testitem ":incoherent_package skips a directory below the unit floor" setup = [Fixtures] tags = [:incoherent_package] begin
    # pkg/ holds two units, both belonging elsewhere. A percentage over that few units
    # reads as 0, 50 or 100 whatever the code does, so the directory is not scored.
    mod = Fixtures.parsedfile(
        :julia,
        "include(\"pkg/one.jl\")\ninclude(\"pkg/two.jl\")\ninclude(\"a/a.jl\")\ninclude(\"b/b.jl\")\n";
        file = "mod.jl"
    )
    one = Fixtures.parsedfile(:julia, "p1() = ay() + az()\n"; file = "pkg/one.jl")
    two = Fixtures.parsedfile(:julia, "p2() = by() + bz()\n"; file = "pkg/two.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a/a.jl")
    b = Fixtures.parsedfile(:julia, "by() = bz()\nbz() = by()\n"; file = "b/b.jl")
    files = [mod, one, two, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    @test isempty(Dendro.cluster_incoherent_packages(files, graph))
end

@testitem ":incoherent_package respects dendro-ignore-file" setup = [Fixtures] tags = [:incoherent_package] begin
    onesrc = "# dendro-ignore-file: incoherent_package\np1() = ay() + az()\n"
    directives = Dendro.suppressions(Fixtures.idx(:julia, onesrc); file = "pkg/one.jl")
    mod = Fixtures.parsedfile(
        :julia,
        "include(\"pkg/one.jl\")\ninclude(\"pkg/two.jl\")\ninclude(\"pkg/three.jl\")\n" *
            "include(\"a/a.jl\")\ninclude(\"b/b.jl\")\ninclude(\"c/c.jl\")\n";
        file = "mod.jl"
    )
    one = Fixtures.parsedfile(:julia, onesrc; file = "pkg/one.jl", directives = directives)
    two = Fixtures.parsedfile(:julia, "p2() = by() + bz()\n"; file = "pkg/two.jl")
    three = Fixtures.parsedfile(:julia, "p3() = cy() + cz()\n"; file = "pkg/three.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a/a.jl")
    b = Fixtures.parsedfile(:julia, "by() = bz()\nbz() = by()\n"; file = "b/b.jl")
    c = Fixtures.parsedfile(:julia, "cy() = cz()\ncz() = cy()\n"; file = "c/c.jl")
    files = [mod, one, two, three, a, b, c]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    @test only(Dendro.cluster_incoherent_packages(files, graph)).suppressed
end

@testitem ":incoherent_package runs only when the config enables it" tags = [:incoherent_package] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        mkpath(joinpath(dir, "pkg"))
        for (d, u) in (("a", "ay"), ("b", "by"), ("c", "cy"))
            mkpath(joinpath(dir, d))
            write(joinpath(dir, d, "$d.jl"), "$(u)() = $(u)2()\n$(u)2() = $(u)()\n")
        end
        for (i, u) in enumerate(("ay", "by", "cy"))
            write(joinpath(dir, "pkg", "p$i.jl"), "p$i() = $(u)() + $(u)2()\n")
        end
        write(
            joinpath(dir, "mod.jl"),
            join("include(\"pkg/p$i.jl\")\n" for i in 1:3) *
                join("include(\"$d/$d.jl\")\n" for d in ("a", "b", "c"))
        )

        off = discover_config([dir]; use_files = false)
        @test isempty(filter(f -> f.metric === :incoherent_package, analyze(dir; config = off)))

        write(joinpath(dir, ".dendro.toml"), "[rules]\nincoherent_package = true\n")
        on = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir])
            end
        end
        hits = filter(f -> f.metric === :incoherent_package, analyze(dir; config = on))
        @test length(hits) == 1
        @test only(hits).value == 100
    end
end
