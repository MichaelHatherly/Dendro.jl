@testitem ":hub flags a crossing and leaves a utility and an orchestrator alone" setup = [Fixtures] tags = [:hub] begin
    # hub.jl is depended on by four files and depends on three, so it propagates a change
    # in either direction. util.jl is depended on by four and depends on nothing;
    # orch.jl depends on four and is depended on by nothing. Only the conjunction is the
    # crossing, which is what `min(fan_in, fan_out)` encodes.
    sources = [
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\nhd(x) = d1(x) + d2(x)\n",
        "util.jl" => "u1(x) = x\n",
        "orch.jl" => "o1(x) = d1(x) + d2(x) + d3(x) + u1(x)\n",
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x) + hb(x) + u1(x)\n",
        "x2.jl" => "x2a(x) = ha(x) + hb(x) + u1(x)\n",
        "y1.jl" => "y1a(x) = hc(x) + hd(x) + u1(x)\n",
        "y2.jl" => "y2a(x) = hc(x) + hd(x) + u1(x)\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    files = [Fixtures.parsedfile(:julia, s; file = p) for (p, s) in [mod; sources]]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)
    findings = Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5)

    @test length(findings) == 1
    f = only(findings)
    @test f.metric == :hub
    @test f.kind == :scalar
    # Four files reference hub.jl and it references three, so the crossing scores three.
    @test f.value == 3
    @test f.absolute == :high
    # One file crosses at all, too few to rank against, so only the absolute band fires.
    @test f.percentile === nothing
    # The file, then one representative per audience: `ha`/`hb` serve x1 and x2, `hc`/`hd`
    # serve y1 and y2, and the two audiences share no consumer.
    @test [(l.file, l.line, l.unit) for l in f.locations] ==
        [("hub.jl", 1, ""), ("hub.jl", 1, "ha"), ("hub.jl", 3, "hc")]
end

@testitem ":hub proposes no split when one audience consumes the whole file" setup = [Fixtures] tags = [:hub] begin
    # Every consumer reaches every definition, so the audiences overlap into one group.
    # A hub that does not split is a warning with no proposal, reported as the file alone.
    whole = "ha(x) + hb(x) + hc(x) + hd(x) + u1(x)"
    sources = [
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\nhd(x) = d1(x) + d2(x)\n",
        "util.jl" => "u1(x) = x\n",
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = $whole\n",
        "x2.jl" => "x2a(x) = $whole\n",
        "y1.jl" => "y1a(x) = $whole\n",
        "y2.jl" => "y2a(x) = $whole\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    files = [Fixtures.parsedfile(:julia, s; file = p) for (p, s) in [mod; sources]]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)
    f = only(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5))

    @test f.value == 3
    @test [(l.file, l.line, l.unit) for l in f.locations] == [("hub.jl", 1, "")]
end

@testitem ":hub names no audience built from singletons" setup = [Fixtures] tags = [:hub] begin
    # `ha`/`hb` serve x1 and x2 together, an audience. `hc` serves y1 alone and `hd` serves
    # y2 alone, two groups of one definition and one consumer each. Those are ordinary use,
    # not seams, so one audience survives the floors and the finding proposes no split.
    sources = [
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\nhd(x) = d1(x) + d2(x)\n",
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x) + hb(x)\n",
        "x2.jl" => "x2a(x) = ha(x) + hb(x)\n",
        "y1.jl" => "y1a(x) = hc(x)\n",
        "y2.jl" => "y2a(x) = hd(x)\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    files = [Fixtures.parsedfile(:julia, s; file = p) for (p, s) in [mod; sources]]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)
    f = only(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5))

    @test f.value == 3
    @test [(l.file, l.line, l.unit) for l in f.locations] == [("hub.jl", 1, "")]
end

@testitem ":hub does not score a corpus below the file floor" setup = [Fixtures] tags = [:hub] begin
    # Fan-in and fan-out both scale with corpus size, and in a small corpus every file
    # touches most of the others, so the reading says nothing about the architecture.
    sources = [
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\n",
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x)\n",
        "x2.jl" => "x2a(x) = hb(x)\n",
        "x3.jl" => "x3a(x) = hc(x)\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    files = [Fixtures.parsedfile(:julia, s; file = p) for (p, s) in [mod; sources]]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)

    @test length(fg.files) < Dendro.MIN_HUB_CORPUS_FILES
    @test isempty(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3)))
    # The same corpus scores once the floor is lowered, so the floor is what silenced it.
    @test !isempty(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5))
end

@testitem ":hub re-reports through the ratchet when its audiences change" setup = [Fixtures] tags = [:hub] begin
    using Dendro

    # A hub's locations carry its audience representatives, so they move when its consumers
    # do, and `fkey` covers every location. A consumer change that merges two audiences
    # rewrites the key and the ratchet calls the finding new. That is the intent: the
    # proposal the finding carried no longer holds.
    root, src = Fixtures.gitrepo()
    write(joinpath(root, ".dendro.toml"), "[bands]\nhub = [2, 3]\n")
    sources = Dict(
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\nhd(x) = d1(x) + d2(x)\n",
        "dep1.jl" => "d1(x) = x\n", "dep2.jl" => "d2(x) = x\n", "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x) + hb(x)\n", "x2.jl" => "x2a(x) = ha(x) + hb(x)\n",
        "y1.jl" => "y1a(x) = hc(x) + hd(x)\n", "y2.jl" => "y2a(x) = hc(x) + hd(x)\n",
    )
    # Filler carries the corpus past MIN_HUB_CORPUS_FILES, which no config retunes.
    for i in 1:13
        sources["pad$i.jl"] = "pad$i(x) = x\n"
    end
    for (name, text) in sources
        write(joinpath(src, name), text)
    end
    write(joinpath(src, "mod.jl"), join("include(\"$n\")\n" for n in sort!(collect(keys(sources)))))
    Fixtures.commit!(root, "a hub with two audiences")

    hubs(fs) = filter(f -> f.metric === :hub, fs)
    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            # In the floor, and matched against the base, so an unchanged corpus is quiet.
            @test length(hubs(Dendro.errors(src))) == 1
            @test isempty(hubs(Dendro.errors(src; since = "HEAD")))

            # x1 now reaches `hc` too, so the two audiences share a consumer and merge:
            # the finding loses its representatives and keys differently.
            write(joinpath(src, "x1.jl"), "x1a(x) = ha(x) + hb(x) + hc(x)\n")
            @test length(hubs(Dendro.errors(src))) == 1
            @test length(hubs(Dendro.errors(src; since = "HEAD"))) == 1
        end
    end
end

@testitem ":hub respects dendro-ignore-file" setup = [Fixtures] tags = [:hub] begin
    hubsrc = "# dendro-ignore-file: hub\nha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\n"
    sources = [
        "hub.jl" => hubsrc,
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x)\n",
        "x2.jl" => "x2a(x) = hb(x)\n",
        "x3.jl" => "x3a(x) = hc(x)\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    directives = Dendro.suppressions(Fixtures.idx(:julia, hubsrc); file = "hub.jl")
    files = [
        Fixtures.parsedfile(:julia, s; file = p, directives = p == "hub.jl" ? directives : Dendro.Directive[])
            for (p, s) in [mod; sources]
    ]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)
    hit = only(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5))

    @test hit.suppressed
end

@testitem ":hub labels each audience representative with the files consuming it" setup = [Fixtures] tags = [:hub] begin
    # The proposed split is only actionable if the finding names who each half serves. The
    # anchor is the file itself, so it carries no label; each representative carries its
    # audience's consumers, the same evidence `:split_audience` attaches.
    sources = [
        "hub.jl" => "ha(x) = d1(x)\nhb(x) = d2(x)\nhc(x) = d3(x)\nhd(x) = d1(x) + d2(x)\n",
        "util.jl" => "u1(x) = x\n",
        "orch.jl" => "o1(x) = d1(x) + d2(x) + d3(x) + u1(x)\n",
        "dep1.jl" => "d1(x) = x\n",
        "dep2.jl" => "d2(x) = x\n",
        "dep3.jl" => "d3(x) = x\n",
        "x1.jl" => "x1a(x) = ha(x) + hb(x) + u1(x)\n",
        "x2.jl" => "x2a(x) = ha(x) + hb(x) + u1(x)\n",
        "y1.jl" => "y1a(x) = hc(x) + hd(x) + u1(x)\n",
        "y2.jl" => "y2a(x) = hc(x) + hd(x) + u1(x)\n",
    ]
    mod = "mod.jl" => join("include(\"$p\")\n" for (p, _) in sources)
    files = [Fixtures.parsedfile(:julia, s; file = p) for (p, s) in [mod; sources]]

    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(files)
    linkage = Dendro.resolve_linkage(files, table)
    fg = Dendro.build_file_graph(files, table, corpus; linkage)
    f = only(Dendro.cluster_hub(files, fg, table; linkage, band = (2, 3), min_files = 5))

    @test [(l.unit, l.label) for l in f.locations] ==
        [("", ""), ("ha", "used by x1.jl, x2.jl"), ("hc", "used by y1.jl, y2.jl")]
end
