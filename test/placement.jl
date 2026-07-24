@testitem ":misplaced flags a unit coupled to another file" setup = [Fixtures] tags = [:placement] begin
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "foo() = bar()\nbar() = foo()\nstray() = baz() + qux() + baz()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "baz() = qux()\nqux() = baz()\n"; file = "b.jl")
    files = [mod, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    findings = Dendro.cluster_misplaced(files, graph, table; min_refs = 2)

    # `stray` in a.jl references only b.jl's functions, never a.jl's, so it couples
    # entirely to b.jl: feature envy. Its neighbourhood (community) is b.jl's, so it is
    # flagged misplaced, with b.jl as the suggested home. `foo`/`bar` and `baz`/`qux`
    # each couple within their own file and are left alone.
    @test length(findings) == 1
    f = only(findings)
    @test f.metric == :misplaced
    @test first(f.locations).file == "a.jl"
    @test first(f.locations).line == 3
    @test f.value == 100
    @test any(loc -> loc.file == "b.jl", f.locations)
end

@testitem ":misplaced respects dendro-ignore-file" setup = [Fixtures] tags = [:placement] begin
    asrc = "# dendro-ignore-file: misplaced\nfoo() = bar()\nbar() = foo()\nstray() = baz() + qux() + baz()\n"
    i = Fixtures.idx(:julia, asrc)
    directives = Dendro.suppressions(i; file = "a.jl")
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, asrc; file = "a.jl", directives = directives)
    b = Fixtures.parsedfile(:julia, "baz() = qux()\nqux() = baz()\n"; file = "b.jl")
    files = [mod, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    hit = only(Dendro.cluster_misplaced(files, graph, table; min_refs = 2))
    @test hit.suppressed
end

@testitem ":misplaced does not fire on a thin candidate set" setup = [Fixtures] tags = [:placement] begin
    # Five files, but only one unit ever scores. `leaner` in a.jl references its own
    # file's `home` three times and b.jl's `baz`/`qux` three times, so its envy is 0.5:
    # below the absolute band. Its community is anchored in b.jl, so it is a candidate,
    # but it is the sole entry in the scored distribution. The percentile must stay
    # silent on a distribution this thin; the corpus file count alone is not enough.
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "home() = 1\nleaner() = home() + home() + home() + baz() + qux() + baz()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "baz() = qux()\nqux() = baz()\n"; file = "b.jl")
    c = Fixtures.parsedfile(:julia, "c1() = 1\n"; file = "c.jl")
    d = Fixtures.parsedfile(:julia, "d1() = 1\n"; file = "d.jl")
    files = [mod, a, b, c, d]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    findings = Dendro.cluster_misplaced(files, graph, table)

    @test isempty(findings)
end

@testitem ":misplaced scores a unit the same whatever else the corpus holds" setup = [Fixtures] tags = [:placement] begin
    # `stray` leans on b.jl's `low1`/`low2`, which nothing else references, and touches
    # g.jl's `wide` once. Four units reach for `wide`, so whether it reads as
    # cross-cutting decides whether that one reference joins `stray`'s mass and dilutes
    # its envy from 100 to 75. That call must turn on the units that can see `wide`, not
    # on how much unrelated source sits alongside.
    m = [
        Fixtures.parsedfile(:julia, join(("include(\"$f.jl\")" for f in ("a", "b", "c", "d", "e", "g")), "\n") * "\n"; file = "mod.jl"),
        Fixtures.parsedfile(:julia, "stray() = low1() + low1() + low2() + wide()\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "low1() = 1\nlow2() = 2\n"; file = "b.jl"),
        Fixtures.parsedfile(:julia, "c1() = wide()\n"; file = "c.jl"),
        Fixtures.parsedfile(:julia, "d1() = wide()\n"; file = "d.jl"),
        Fixtures.parsedfile(:julia, "e1() = wide()\n"; file = "e.jl"),
        Fixtures.parsedfile(:julia, "wide() = 3\n"; file = "g.jl"),
    ]
    # Unrelated source: no include ties it to the module above, so neither can see the
    # other's names. It must not reach the verdict at all.
    pad = [Fixtures.parsedfile(:julia, "pad$(i)a() = $(i)\npad$(i)b() = pad$(i)a()\n"; file = "pad$(i).jl") for i in 1:60]

    function verdict(files)
        table = Dendro.corpus_symbols(files)
        graph = Dendro.build_corpus_graph(files, table)
        return [(first(f.locations).file, first(f.locations).line, f.value) for f in Dendro.cluster_misplaced(files, graph, table)]
    end

    @test verdict(m) == [("a.jl", 1, 100)]
    @test verdict([m; pad]) == verdict(m)
end

@testitem ":misplaced leaves a well-placed unit alone" setup = [Fixtures] tags = [:placement] begin
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    # `mix` references its own file's `helper` twice and b.jl's `ext` once: mostly home,
    # so its envy is low and it is not flagged.
    a = Fixtures.parsedfile(:julia, "helper(x) = x\nmix() = helper(helper(ext()))\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "ext() = 1\nother() = ext()\n"; file = "b.jl")
    files = [mod, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    findings = Dendro.cluster_misplaced(files, graph, table; min_refs = 1)

    @test isempty(findings)
end
