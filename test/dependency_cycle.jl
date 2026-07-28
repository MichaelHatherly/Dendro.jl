@testitem "a three-file cycle is reported as the weak edge that breaks it" setup = [Fixtures] tags = [:dependency_cycle] begin
    # a leans hard on b, b on c, and c names one thing in a. The one reference is the
    # cheapest edge to remove, so it is the cut the finding has to name.
    files = [
        Fixtures.parsedfile(:julia, "include(\"b.jl\")\nfa(x) = gb(x) + gb(x + 1) + gb(x + 2)\nga(y) = y\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "include(\"c.jl\")\nfb(x) = gc(x) + gc(x + 1) + gc(x + 2)\ngb(y) = y\n"; file = "b.jl"),
        Fixtures.parsedfile(:julia, "include(\"a.jl\")\nfc(x) = ga(x)\ngc(y) = y\n"; file = "c.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    @test length(findings) == 1
    # The score is the component size, the count of files caught in the cycle.
    @test findings[1].value == 3
    # One cut breaks it, at the include statement admitting the edge.
    @test [(l.file, l.line) for l in findings[1].locations] == [("c.jl", 1)]
    @test findings[1].locations[1].unit == "cut -> a.jl"
end

@testitem "a five-file cycle names its weak link" setup = [Fixtures] tags = [:dependency_cycle] begin
    # Four heavy edges around the ring and one light one closing it. The heuristic is
    # weighted by reference count, so the light edge is what it proposes cutting.
    heavy(from, to) = "include(\"$to.jl\")\nf$from(x) = g$to(x) + g$to(x + 1) + g$to(x + 2)\ng$from(y) = y\n"
    files = [
        Fixtures.parsedfile(:julia, heavy("a", "b"); file = "a.jl"),
        Fixtures.parsedfile(:julia, heavy("b", "c"); file = "b.jl"),
        Fixtures.parsedfile(:julia, heavy("c", "d"); file = "c.jl"),
        Fixtures.parsedfile(:julia, heavy("d", "e"); file = "d.jl"),
        Fixtures.parsedfile(:julia, "include(\"a.jl\")\nfe(x) = ga(x)\nge(y) = y\n"; file = "e.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 6))
    @test length(findings) == 1
    @test findings[1].value == 5
    @test [(l.file, l.unit) for l in findings[1].locations] == [("e.jl", "cut -> a.jl")]
end

@testitem "a layered corpus with no cycle reports nothing" setup = [Fixtures] tags = [:dependency_cycle] begin
    files = [
        Fixtures.parsedfile(:julia, "include(\"b.jl\")\nfa(x) = gb(x) + gb(x + 1)\nga(y) = y\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "include(\"c.jl\")\nfb(x) = gc(x) + gc(x + 1)\ngb(y) = y\n"; file = "b.jl"),
        Fixtures.parsedfile(:julia, "gc(y) = y\n"; file = "c.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # Dependencies run one way down the layers. Nothing to break, so nothing to report.
    @test isempty(Dendro.cluster_dependency_cycles(files, fg; band = (2, 4)))
end

@testitem "two disjoint cycles are two findings" setup = [Fixtures] tags = [:dependency_cycle] begin
    ring(from, to) = "include(\"$to.jl\")\nf$from(x) = g$to(x)\ng$from(y) = y\n"
    files = [
        Fixtures.parsedfile(:julia, ring("a", "b"); file = "a.jl"),
        Fixtures.parsedfile(:julia, ring("b", "a"); file = "b.jl"),
        Fixtures.parsedfile(:julia, ring("p", "q"); file = "p.jl"),
        Fixtures.parsedfile(:julia, ring("q", "r"); file = "q.jl"),
        Fixtures.parsedfile(:julia, ring("r", "p"); file = "r.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    # Two strongly connected components, so two findings: each names its own edit.
    @test length(findings) == 2
    @test [f.value for f in findings] == [3, 2]
    @test Set(l.file for f in findings for l in f.locations) ⊆ Set(["a.jl", "b.jl", "p.jl", "q.jl", "r.jl"])
end

@testitem "a component too tangled to cut reports the tangle" setup = [Fixtures] tags = [:dependency_cycle] begin
    # Eight files each referencing every other: 28 edges point backwards whatever the
    # arrangement, so no bounded edit exists and the finding must say so rather than
    # dress a truncated list up as the cuts to make.
    names = ["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8"]
    body(self) = string(
        join("include(\"$o.jl\")\n" for o in names if o != self),
        "f$self(x) = ", join("g$o(x)" for o in names if o != self), "\n",
        "g$self(y) = y\n"
    )
    files = [Fixtures.parsedfile(:julia, body(n); file = "$n.jl") for n in names]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    @test length(findings) == 1
    @test findings[1].value == 8
    # The locations are the tangle's busiest members, capped, and every one of them says
    # it is a tangle and how many cuts the report is no longer naming.
    @test length(findings[1].locations) == Dendro.CYCLE_LOCATIONS_MAX
    @test all(l -> l.unit == "tangled: 28 cuts", findings[1].locations)
    # Every member carries the same degree here, so the path breaks the tie: a report of a
    # tangle is as reproducible as one naming an edit.
    @test [l.file for l in findings[1].locations] == ["t1.jl", "t2.jl", "t3.jl", "t4.jl", "t5.jl", "t6.jl"]
end

@testitem "a cycle finding is suppressible inline" setup = [Fixtures] tags = [:dependency_cycle] begin
    src_c = "# dendro-ignore: dependency_cycle\ninclude(\"a.jl\")\nfc(x) = ga(x)\ngc(y) = y\n"
    files = [
        Fixtures.parsedfile(:julia, "include(\"b.jl\")\nfa(x) = gb(x) + gb(x + 1)\nga(y) = y\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "include(\"c.jl\")\nfb(x) = gc(x) + gc(x + 1)\ngb(y) = y\n"; file = "b.jl"),
        Fixtures.parsedfile(
            :julia, src_c; file = "c.jl",
            directives = Dendro.suppressions(Fixtures.idx(:julia, src_c); file = "c.jl")
        ),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    # Accepted, not hidden: the finding stays in the vector carrying its mark.
    @test length(findings) == 1
    @test findings[1].suppressed
end

@testitem "the feedback set cuts the light edge, not the heavy one" setup = [Fixtures] tags = [:dependency_cycle] begin
    # Two files leaning on each other, one direction far heavier. Removing the heavy edge
    # would be a much larger edit for the same acyclic result, so the heuristic must not
    # propose it.
    files = [
        Fixtures.parsedfile(:julia, "include(\"b.jl\")\nfa(x) = gb(x) + gb(x + 1) + gb(x + 2) + gb(x + 3)\nga(y) = y\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "include(\"a.jl\")\nfb(x) = ga(x)\ngb(y) = y\n"; file = "b.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    @test length(findings) == 1
    @test [(l.file, l.unit) for l in findings[1].locations] == [("b.jl", "cut -> a.jl")]
end

@testitem "every relational band lands on its own Config field" tags = [:dependency_cycle, :config] begin
    using Dendro: RELATIONAL_BANDS, discover_config

    # `Config` is built positionally and every relational band has the same type, so a
    # merge that reorders those arguments compiles, typechecks, and attaches each band to
    # the wrong metric in silence. Giving each one a distinct value and asserting them
    # individually is what makes that reorder fail loudly.
    mktempdir() do dir
        bands = Dict(name => (10 * i, 10 * i + 1) for (i, name) in enumerate(RELATIONAL_BANDS))
        toml = joinpath(dir, "c.toml")
        write(toml, string("[bands]\n", join("$name = [$(b[1]), $(b[2])]\n" for (name, b) in bands)))
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = toml)
            end
        end
        for name in RELATIONAL_BANDS
            @test getfield(cfg, name) == bands[name]
        end
    end
end

@testitem "a config band reaches the cycle rule" tags = [:dependency_cycle] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        # A three-file cycle, under the default band and over the configured one. The band
        # is positional in `Config`, so this pins that it lands on this metric and not a
        # neighbouring one.
        write(joinpath(dir, "a.jl"), "include(\"b.jl\")\nfa(x) = gb(x) + gb(x + 1)\nga(y) = y\n")
        write(joinpath(dir, "b.jl"), "include(\"c.jl\")\nfb(x) = gc(x) + gc(x + 1)\ngb(y) = y\n")
        write(joinpath(dir, "c.jl"), "include(\"a.jl\")\nfc(x) = ga(x)\ngc(y) = y\n")
        toml = joinpath(dir, "c.toml")
        write(toml, "[bands]\ndependency_cycle = [2, 3]\n")
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = toml)
            end
        end
        @test cfg.dependency_cycle == (2, 3)

        cycles(fs) = filter(f -> f.metric === :dependency_cycle, fs)
        @test isempty(cycles(analyze(dir)))
        tuned = only(cycles(analyze(dir; config = cfg)))
        @test tuned.value == 3
        @test tuned.absolute === :high
    end
end

@testitem "the reference count, not the node order, picks the cut" setup = [Fixtures] tags = [:dependency_cycle] begin
    # A ring whose weights and whose node order disagree. a -> b carries one reference,
    # b -> c five, c -> a three. The weighted arrangement cuts a -> b; flatten every weight
    # to one and the same code cuts c -> a instead, because the index tie-break takes over.
    # So this fixture fails if the weighting is ever dropped, which the even-weighted rings
    # above cannot detect.
    files = [
        Fixtures.parsedfile(:julia, "include(\"b.jl\")\nfa(x) = gb(x)\nga(y) = y\n"; file = "a.jl"),
        Fixtures.parsedfile(
            :julia,
            "include(\"c.jl\")\nfb(x) = gc(x) + gc(x + 1) + gc(x + 2) + gc(x + 3) + gc(x + 4)\ngb(y) = y\n";
            file = "b.jl"
        ),
        Fixtures.parsedfile(:julia, "include(\"a.jl\")\nfc(x) = ga(x) + ga(x + 1) + ga(x + 2)\ngc(y) = y\n"; file = "c.jl"),
    ]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)
    @test fg.edges[(fg.index["a.jl"], fg.index["b.jl"])].weight == 1
    @test fg.edges[(fg.index["b.jl"], fg.index["c.jl"])].weight == 5
    @test fg.edges[(fg.index["c.jl"], fg.index["a.jl"])].weight == 3

    findings = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
    @test [(l.file, l.unit) for l in findings[1].locations] == [("a.jl", "cut -> b.jl")]
end

@testitem "a cut label survives the ratchet's base revision" tags = [:gate, :dependency_cycle] setup = [Fixtures] begin
    using Dendro

    # A ten-file ring: over the high band, and one cut breaks it, so the finding is the
    # kind whose locations carry a `cut -> target` label. `fkey` keys on that label
    # verbatim while it makes the file path repo-relative, and the base revision is scored
    # in a `git archive` tempdir. A label naming an absolute path would differ between the
    # two roots, so a pre-existing cycle would re-report as new on every ratchet run.
    root, src = Fixtures.gitrepo()
    for i in 1:10
        nxt = i == 10 ? 1 : i + 1
        write(joinpath(src, "r$i.jl"), "include(\"r$nxt.jl\")\nf$i(x) = g$nxt(x)\ng$i(y) = y\n")
    end
    Fixtures.commit!(root, "a ring of ten")

    floor = Dendro.errors(src)
    @test length(filter(f -> f.metric === :dependency_cycle, floor)) == 1
    # The label is relative to the file the import sits in, so it reads the way the
    # statement being removed does.
    cycle = only(filter(f -> f.metric === :dependency_cycle, floor))
    @test all(l -> startswith(l.unit, "cut -> r"), cycle.locations)

    # The working tree matches HEAD, so the ratchet compares the same code against itself,
    # scored once in place and once in the archive tempdir. A non-empty floor with an empty
    # ratchet is what proves every key matched across the two roots; a label naming an
    # absolute path would miss and re-report the whole floor.
    @test !isempty(floor)
    @test isempty(Dendro.errors(src; since = "HEAD"))
end

@testitem "the percentile carries a small cycle the band leaves alone" setup = [Fixtures] tags = [:dependency_cycle] begin
    # Six two-file cycles and one four-file cycle. Every one of them sits under the
    # default absolute band, and the corpus-relative half is what reports the outlier:
    # this is the case the two-score model exists for.
    pair(from, to) = "include(\"$to.jl\")\nf$from(x) = g$to(x)\ng$from(y) = y\n"
    files = Dendro.ParsedFile[]
    for i in 1:6
        push!(files, Fixtures.parsedfile(:julia, pair("p$(i)a", "p$(i)b"); file = "p$(i)a.jl"))
        push!(files, Fixtures.parsedfile(:julia, pair("p$(i)b", "p$(i)a"); file = "p$(i)b.jl"))
    end
    for (i, nxt) in enumerate([2, 3, 4, 1])
        push!(files, Fixtures.parsedfile(:julia, pair("q$i", "q$nxt"); file = "q$i.jl"))
    end
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    findings = Dendro.cluster_dependency_cycles(files, fg)
    @test length(findings) == 1
    @test findings[1].value == 4
    @test findings[1].absolute == :ok
    @test findings[1].percentile == 1.0
end
