@testitem ":distant_definition flags a definition sitting far from its nearest use" setup = [Fixtures] tags = [:distant_definition] begin
    # `MESSAGE` is read only by `use`, four definitions further down the file. The score is
    # that count of definitions between the two, and the second location is the use.
    src = """
    const MESSAGE = "boom"

    a() = 1
    b() = 2
    c() = 3
    d() = 4

    use() = MESSAGE
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    table = Dendro.corpus_symbols(files)
    findings = Dendro.cluster_distant_definition(files, table; band = (3, 5))

    f = only(findings)
    @test f.metric == :distant_definition
    @test f.kind == :scalar
    @test f.value == 4
    @test f.absolute == :warn
    # One file, so the percentile stays off and the absolute band alone fires.
    @test f.percentile === nothing
    @test [(l.unit, l.line) for l in f.locations] == [("MESSAGE", 1), ("use", 8)]
    @test last(f.locations).label == "nearest use of MESSAGE"
end

@testitem ":distant_definition leaves a definition beside its use alone" setup = [Fixtures] tags = [:distant_definition] begin
    # `MESSAGE` is read by the definition directly below it, so nothing sits between them.
    src = """
    const MESSAGE = "boom"
    use() = MESSAGE

    a() = 1
    b() = 2
    c() = 3
    d() = 4
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    @test isempty(Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (3, 5)))
end

@testitem ":distant_definition scores the nearest use, not the mean of them" setup = [Fixtures] tags = [:distant_definition] begin
    # `h` is read from the top of the file and from the bottom. A file-wide helper has a use
    # close by wherever it sits, which is what keeps the rule quiet on one without a
    # ubiquity cut: the score is the gap to the nearest use, here zero.
    src = """
    top() = h()
    h() = 1
    a() = 1
    b() = 2
    c() = 3
    bottom() = h()
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    @test isempty(Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (2, 3)))
end

@testitem ":distant_definition reads a use above the definition too" setup = [Fixtures] tags = [:distant_definition] begin
    # Julia resolves a top-level name whatever the order, so a definition can sit below
    # everything that uses it. The distance is what the rule reads, not the direction.
    src = """
    use() = MESSAGE
    a() = 1
    b() = 2
    c() = 3
    const MESSAGE = "boom"
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    findings = Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (3, 5))
    f = only(findings)
    @test f.value == 3
    @test [(l.unit, l.line) for l in f.locations] == [("MESSAGE", 5), ("use", 1)]
end

@testitem ":distant_definition counts a nested definition with the unit holding it" setup = [Fixtures] tags = [:distant_definition] begin
    # `a` holds a nested short-form definition, which is a unit of its own. A reader
    # scrolling from `MESSAGE` to `use` passes one definition, not two, so the nested unit
    # takes its parent's place in the count rather than a place of its own.
    src = """
    const MESSAGE = "boom"
    function a()
        inner(x) = x + 1
        return inner(1)
    end
    use() = MESSAGE
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    f = only(Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (1, 2)))
    @test f.value == 1
end

@testitem ":distant_definition respects dendro-ignore" setup = [Fixtures] tags = [:distant_definition] begin
    src = """
    # dendro-ignore: distant_definition
    const MESSAGE = "boom"

    a() = 1
    b() = 2
    c() = 3
    d() = 4

    use() = MESSAGE
    """
    index = Fixtures.idx(:julia, src)
    files = [
        Fixtures.parsedfile(
            :julia, src; file = "f.jl", directives = Dendro.suppressions(index; file = "f.jl")
        ),
    ]
    f = only(Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (3, 5)))
    @test f.suppressed
end

@testitem ":distant_definition runs only when the config enables it" tags = [:distant_definition] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        # `MESSAGE` and its one use sit either side of six definitions, a gap of six. The
        # band is tightened to a project that defines beside the use, which is the layer
        # this opinion belongs in.
        write(
            joinpath(dir, "f.jl"),
            "const MESSAGE = 1\n" * join("h$i() = $i\n" for i in 1:6) * "use() = MESSAGE\n"
        )

        off = discover_config([dir]; use_files = false)
        @test isempty(filter(f -> f.metric === :distant_definition, analyze(dir; config = off)))

        write(
            joinpath(dir, ".dendro.toml"),
            "[rules]\ndistant_definition = true\n\n[bands]\ndistant_definition = [5, 10]\n"
        )
        on = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir])
            end
        end
        hits = filter(f -> f.metric === :distant_definition, analyze(dir; config = on))
        @test only(hits).value == 6
    end
end

@testitem ":distant_definition says nothing without resolved bindings" setup = [Fixtures] tags = [:distant_definition] begin
    # Without bindings there is no reference to measure a distance from, so the pass says
    # nothing rather than reading every definition as adjacent to nothing.
    files = [Fixtures.parsedfile(:julia, "const M = 1\na() = 1\nb() = M\n"; file = "f.jl")]
    empty!(files[1].index.bindings)
    @test isempty(Dendro.cluster_distant_definition(files, Dendro.corpus_symbols(files); band = (0, 1)))
end
