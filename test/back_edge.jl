@testitem "back edge flags the minority direction of a dominated pair" setup = [Fixtures] tags = [:back_edge] begin
    # core/ <- api/ <- cli/ is the grain: api leans hard on core, cli on api. The planted
    # reference from core back into api is the anomaly.
    heavy = join(("core_a(x)" for _ in 1:10), " + ") * " + " * join(("core_b(x)" for _ in 1:10), " + ")
    files = [
        Fixtures.parsedfile(
            :julia,
            "include(\"../api/render.jl\")\ncore_a(x) = x\ncore_b(x) = x\ncore_c(x) = render(x)\n";
            file = "core/core.jl"
        ),
        Fixtures.parsedfile(
            :julia, "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $heavy\n"; file = "api/render.jl"
        ),
        Fixtures.parsedfile(
            :julia, "include(\"../api/render.jl\")\nmain(x) = usec(x) + render(x)\n"; file = "cli/main.jl"
        ),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)
    findings = Dendro.cluster_back_edge(files, fg, table; band = (85, 95))

    # api names core 20 times, core names api once: 95% of the traffic between the two
    # directories runs one way, and the 1% going back is the edit the finding proposes.
    finding = only(findings)
    @test finding.metric === :back_edge
    @test finding.value == 95
    @test finding.absolute === :high
    # cli reaches into api and api never reaches back, so that pair has no minority
    # direction and is never scored.
    @test all(loc -> startswith(loc.file, "core/"), finding.locations)
end

@testitem "back edge points at the import first, then every reference" setup = [Fixtures] tags = [:back_edge] begin
    heavy = join(("core_a(x)" for _ in 1:20), " + ")
    files = [
        Fixtures.parsedfile(
            :julia,
            "include(\"../api/render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\ncore_d(x) = render(x) + 1\n";
            file = "core/core.jl"
        ),
        Fixtures.parsedfile(
            :julia, "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $heavy\n"; file = "api/render.jl"
        ),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)
    finding = only(Dendro.cluster_back_edge(files, fg, table; band = (85, 95)))

    # The whole proposed edit is "drop this import and move what needed it", so the import
    # leads. Each reference across the edge follows, so a diff that adds a use of an
    # already-imported name still scopes the finding in.
    @test [(l.file, l.line, l.unit) for l in finding.locations] == [
        ("core/core.jl", 1, ""), ("core/core.jl", 3, "core_c"), ("core/core.jl", 4, "core_d"),
    ]
end

@testitem "back edge dominance falls as the minority direction grows" setup = [Fixtures] tags = [:back_edge] begin
    heavy = join(("core_a(x)" for _ in 1:20), " + ")

    # `backs` extra units in core, each naming one definition in api.
    function dominance(backs::Int)
        core = "include(\"../api/render.jl\")\ncore_a(x) = x\n" *
            join("core_b$i(x) = render(x) + $i\n" for i in 1:backs)
        files = [
            Fixtures.parsedfile(:julia, core; file = "core/core.jl"),
            Fixtures.parsedfile(
                :julia, "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $heavy\n"; file = "api/render.jl"
            ),
        ]
        table = Dendro.corpus_symbols(files)
        corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
        fg = Dendro.build_file_graph(files, table, corpus)
        return Dendro.cluster_back_edge(files, fg, table; band = (85, 95))
    end

    # One stray reference against 20 is a clear violation of an established grain; four is
    # a pair that couples both ways, which is a cycle rather than a back edge and is not
    # this rule's finding.
    @test only(dominance(1)).value == 95
    @test only(dominance(2)).value == 91
    @test isempty(dominance(4))
end

@testitem "back edge leaves a pair with no established grain alone" setup = [Fixtures] tags = [:back_edge] begin
    light = join(("core_a(x)" for _ in 1:5), " + ")
    files = [
        Fixtures.parsedfile(
            :julia, "include(\"../api/render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\n"; file = "core/core.jl"
        ),
        Fixtures.parsedfile(
            :julia, "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $light\n"; file = "api/render.jl"
        ),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # Five references one way and one the other is not a direction the code has settled
    # on, so there is no grain for the minority to run against. The pair is dropped before
    # it is scored at all, not merely scored low: lowering the floor brings it back.
    @test isempty(Dendro.cluster_back_edge(files, fg, table; band = (80, 95)))
    @test only(Dendro.cluster_back_edge(files, fg, table; band = (80, 95), min_major = 5)).value == 83
end

@testitem "back edge fires on the corpus percentile alone" setup = [Fixtures] tags = [:back_edge] begin
    # Six directories chained so each neighbouring pair couples both ways, the minority
    # direction growing along the chain: dominances run 95, 91, 87, 83, 80.
    files = Dendro.ParsedFile[]
    for i in 1:6
        src = "t$i(x) = x\n"
        i > 1 && (src *= "heavy$i(x) = " * join(("t$(i - 1)(x)" for _ in 1:20), " + ") * "\n")
        i < 6 && (src *= "back$i(x) = " * join(("t$(i + 1)(x)" for _ in 1:i), " + ") * "\n")
        push!(files, Fixtures.parsedfile(:julia, src; file = "m$i/f$i.jl"))
    end
    push!(files, Fixtures.parsedfile(:julia, join("include(\"m$i/f$i.jl\")\n" for i in 1:6); file = "all.jl"))
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # An unreachable band isolates the corpus-relative half. The worst pair in a corpus of
    # five still reads as an outlier against its own distribution, which is the trap the
    # absolute band alone leaves open in a uniformly-coupled codebase.
    findings = Dendro.cluster_back_edge(files, fg, table; band = (200, 300), cut = 0.95)
    @test length(findings) == 1
    @test only(findings).value == 95
    @test only(findings).percentile == 1.0
    @test only(findings).absolute === :ok
end

@testitem "back edge re-reports when a diff deepens it" setup = [Fixtures] tags = [:back_edge] begin
    # The location set is the ratchet key, and it grows with each reference across the
    # edge, so adding one re-reports a finding the base already carried. That is the
    # behaviour the rule wants: the edit made the coupling worse.
    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(srcdir, "core"))
    mkpath(joinpath(srcdir, "api"))
    heavy = join(("core_a(x)" for _ in 1:40), " + ")
    write(
        joinpath(srcdir, "api", "render.jl"),
        "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $heavy\n"
    )
    core = joinpath(srcdir, "core", "core.jl")
    write(core, "include(\"../api/render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\n")
    Fixtures.commit!(root, "grain")

    # Committed and unchanged: the violation predates the ref, so the ratchet stays quiet.
    @test isempty(filter(f -> f.metric === :back_edge, Dendro.errors(srcdir; since = "HEAD")))

    write(core, "include(\"../api/render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\ncore_d(x) = render(x) + 1\n")
    reported = only(filter(f -> f.metric === :back_edge, Dendro.errors(srcdir; since = "HEAD")))
    @test reported.absolute === :high
    @test length(reported.locations) == 3
end

@testitem "back edge is suppressible inline" setup = [Fixtures] tags = [:back_edge] begin
    heavy = join(("core_a(x)" for _ in 1:20), " + ")
    mktempdir() do dir
        mkpath(joinpath(dir, "core"))
        mkpath(joinpath(dir, "api"))
        write(joinpath(dir, "api", "render.jl"), "include(\"../core/core.jl\")\nrender(y) = y\nusec(x) = $heavy\n")
        write(
            joinpath(dir, "core", "core.jl"),
            "# dendro-ignore: back_edge\ninclude(\"../api/render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\n"
        )

        # Deliberate callbacks and plugin registration point backwards on purpose. The
        # answer is a suppression, and the finding stays in the count rather than
        # vanishing. The global config layer is isolated so a developer's own file cannot
        # retune the band under the assertion.
        findings = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                filter(f -> f.metric === :back_edge, Dendro.analyze(dir))
            end
        end
        @test only(findings).suppressed
        @test isempty(Dendro.active(Dendro.Findings(findings)))
    end
end

@testitem "a wide minority side reports without gating" setup = [Fixtures] tags = [:back_edge] begin
    # `n` minority file edges, each one core file naming one definition in api, against 20
    # references per file the other way. Dominance is 20n/21n whatever `n` is, so the pair
    # sits at 95 and only the width of its minority side changes.
    function spread(n::Int)
        files = Dendro.ParsedFile[]
        for i in 1:n
            push!(
                files,
                Fixtures.parsedfile(:julia, "t$i(x) = x\nback$i(x) = api_helper(x)\n"; file = "core/c$i.jl")
            )
        end
        heavy = join((join(("t$i(x)" for _ in 1:20), " + ") for i in 1:n), " + ")
        push!(files, Fixtures.parsedfile(:julia, "api_helper(y) = y\nusea(x) = $heavy\n"; file = "api/a.jl"))
        includes = join("include(\"core/c$i.jl\")\n" for i in 1:n) * "include(\"api/a.jl\")\n"
        push!(files, Fixtures.parsedfile(:julia, includes; file = "all.jl"))
        table = Dendro.corpus_symbols(files)
        fg = Dendro.build_file_graph(files, table, Dendro.Corpus(files))
        return Dendro.cluster_back_edge(files, fg, table; band = (85, 95))
    end

    # At the cap the pair still names a bounded edit, so it gates as any back edge does.
    narrow = spread(Dendro.BACK_EDGE_EDGE_CAP)
    @test length(narrow) == Dendro.BACK_EDGE_EDGE_CAP
    @test all(f -> f.absolute === :high, narrow)
    @test all(f -> f.value == 95, narrow)

    # One edge wider and there is no single edit to propose, so the same observation is
    # still reported at every edge and stops entering the error floor. A burst of gate
    # errors from one architectural observation is what this prevents.
    wide = spread(Dendro.BACK_EDGE_EDGE_CAP + 1)
    @test length(wide) == Dendro.BACK_EDGE_EDGE_CAP + 1
    @test !any(f -> f.absolute === :high, wide)
    @test all(f -> f.absolute === :warn, wide)
    @test all(f -> f.value == 95, wide)
    # Every minority edge is still named; the finding is demoted, never dropped.
    @test length(unique(first(f.locations).file for f in wide)) == Dendro.BACK_EDGE_EDGE_CAP + 1
end

@testitem "a shallow tree has no directory pairs to score" setup = [Fixtures] tags = [:back_edge] begin
    heavy = join(("core_a(x)" for _ in 1:20), " + ")
    files = [
        Fixtures.parsedfile(
            :julia, "include(\"render.jl\")\ncore_a(x) = x\ncore_c(x) = render(x)\n"; file = "core.jl"
        ),
        Fixtures.parsedfile(:julia, "include(\"core.jl\")\nrender(y) = y\nusec(x) = $heavy\n"; file = "render.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # Everything in one directory contracts to one node, and a group depending on itself
    # says nothing. File-to-file bidirectionality is ordinary and would be noise.
    @test isempty(Dendro.cluster_back_edge(files, fg, table; band = (85, 95)))
end
