@testitem ":scattered flags a file whose units are pulled into different files" setup = [Fixtures] tags = [:scattered] begin
    # foo.jl's two units share no binding: `fa` couples only to a.jl, `fb` only to b.jl.
    # Each is drawn into a different other file's community, so foo.jl is scattered.
    mod = Fixtures.parsedfile(:julia, "include(\"foo.jl\")\ninclude(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    foo = Fixtures.parsedfile(:julia, "fa() = ay() + az()\nfb() = by() + bz()\n"; file = "foo.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "by() = bz()\nbz() = by()\n"; file = "b.jl")
    files = [mod, foo, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    findings = Dendro.cluster_scattered(files, graph; band = (2, 3))

    @test length(findings) == 1
    f = only(findings)
    @test f.metric == :scattered
    @test f.kind == :scalar
    @test f.value == 2
    @test f.absolute == :warn
    # Four files, so the percentile gate stays off: only the absolute band fires.
    @test f.percentile === nothing
    # One representative per elsewhere-anchored community, ordered by line.
    @test [(l.unit, l.line) for l in f.locations] == [("fa", 1), ("fb", 2)]
end

@testitem ":scattered leaves a cohesive file alone" setup = [Fixtures] tags = [:scattered] begin
    # foo.jl's units share the file-local helper `h`, so the within-file edges hold them
    # in one community despite `fa`'s single call out to a.jl. Without folding those edges
    # in, `fa` would be pulled to a.jl and the file would read as scattered.
    mod = Fixtures.parsedfile(:julia, "include(\"foo.jl\")\ninclude(\"a.jl\")\n"; file = "mod.jl")
    foo = Fixtures.parsedfile(:julia, "h() = 1\nfa() = h() + ay()\nfb() = h() + fa()\n"; file = "foo.jl")
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a.jl")
    files = [mod, foo, a]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    @test isempty(Dendro.cluster_scattered(files, graph; band = (2, 3)))
end

@testitem ":scattered ignores a bag of independent functions that :low_cohesion flags" setup = [Fixtures] tags = [:scattered] begin
    # Three functions with no shared binding and no cross-file reference. Each is its own
    # single-unit community, anchored in its own file, so nothing is pulled elsewhere:
    # not scattered. `:low_cohesion` flags the same file as three components. The split
    # between the two metrics: scattering is about external pull, cohesion about internal.
    files = [Fixtures.parsedfile(:julia, "p() = 1\nq() = 2\nr() = 3\n"; file = "c.jl")]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    @test isempty(Dendro.cluster_scattered(files, graph; band = (2, 3)))
    @test !isempty(Dendro.cluster_low_cohesion(files, graph; band = (2, 3)))
end

@testitem ":scattered respects dendro-ignore-file" setup = [Fixtures] tags = [:scattered] begin
    foosrc = "# dendro-ignore-file: scattered\nfa() = ay() + az()\nfb() = by() + bz()\n"
    i = Fixtures.idx(:julia, foosrc)
    directives = Dendro.suppressions(i; file = "foo.jl")
    mod = Fixtures.parsedfile(:julia, "include(\"foo.jl\")\ninclude(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    foo = Fixtures.parsedfile(:julia, foosrc; file = "foo.jl", directives = directives)
    a = Fixtures.parsedfile(:julia, "ay() = az()\naz() = ay()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "by() = bz()\nbz() = by()\n"; file = "b.jl")
    files = [mod, foo, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    hit = only(Dendro.cluster_scattered(files, graph; band = (2, 3)))
    @test hit.suppressed
end
