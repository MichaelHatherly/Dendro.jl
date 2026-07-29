@testitem ":divisible_package proposes a folder per cohesive group" setup = [Fixtures] tags = [:divisible_package] begin
    # Three groups of eight files, each group referencing only itself. Nothing crosses
    # between them, so each group is a subdirectory waiting to be made.
    files = Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8])
    fg = Fixtures.filegraph(files)
    findings = Dendro.cluster_divisible_packages(files, fg)

    f = only(findings)
    @test f.metric == :divisible_package
    @test f.kind == :scalar
    # Every group's references stay inside it, so the best folder is fully internal.
    @test f.value == 100
    @test f.absolute == :high
    # One scored directory, too few to rank against, so only the absolute band fires.
    @test f.percentile === nothing
    # The directory, then one representative file per proposed folder, each labelled with
    # what it holds. All 24 children are placed, so nothing stays at the top level.
    @test [(l.file, l.label) for l in f.locations] == [
        ("pkg/g1u1.jl", "pkg, 24 of 24 children placed"),
        ("pkg/g1u1.jl", "8 children, 100% internal"),
        ("pkg/g2u1.jl", "8 children, 100% internal"),
        ("pkg/g3u1.jl", "8 children, 100% internal"),
    ]
end

@testitem ":divisible_package groups sibling directories under new parents" setup = [Fixtures] tags = [:divisible_package] begin
    # The same construction with each unit in its own subdirectory: pkg/ now holds fifteen
    # directories and no loose files. A child directory is one node with everything under
    # it contracted in, so the reading is the same one and the proposal groups directories
    # rather than files.
    files = Fixtures.layout_corpus("pkg"; sizes = [5, 5, 5], nest = true)
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_divisible_packages(files, fg))
    @test f.value == 100
    @test [(l.file, l.label) for l in f.locations] == [
        ("pkg/g1u1/impl.jl", "pkg, 15 of 15 children placed"),
        ("pkg/g1u1/impl.jl", "5 children, 100% internal"),
        ("pkg/g2u1/impl.jl", "5 children, 100% internal"),
        ("pkg/g3u1/impl.jl", "5 children, 100% internal"),
    ]
end

@testitem ":divisible_package extracts one group and leaves the rest loose" setup = [Fixtures] tags = [:divisible_package] begin
    # One cohesive group of eight beside twelve files that reference everything
    # indiscriminately. A directory is not partitioned: the folder comes out and the
    # miscellaneous files stay where they are, which the label records.
    files = Fixtures.layout_corpus("pkg"; sizes = [8], loose = 12)
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_divisible_packages(files, fg))
    @test f.absolute == :warn
    # One folder proposed; the other candidate group is too entangled to clear the bar.
    @test length(f.locations) == 2
    @test first(f.locations).label == "pkg, 8 of 20 children placed"
    @test last(f.locations).label == "8 children, 81% internal"
end

@testitem ":divisible_package stays silent on an entangled directory" setup = [Fixtures] tags = [:divisible_package] begin
    # The same three groups, now with four cross-references per file. The groups are still
    # there, but separating them would trade one tangle for another, so no group clears the
    # bar and the directory reports nothing.
    files = Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8], cross = 4)
    fg = Fixtures.filegraph(files)

    @test isempty(Dendro.cluster_divisible_packages(files, fg))
    reading = Dendro.read_divisible(fg, "pkg")
    @test round(Int, 100 * reading.candidates[1].ratio) < Dendro.DIVISIBLE_PACKAGE_BAND[1]
end

@testitem ":divisible_package stays silent when no group is large enough to be a folder" setup = [Fixtures] tags = [:divisible_package] begin
    # Eight independent families of three. Each is genuinely separate and the split is
    # perfect, but `pkg/int` and `pkg/double` holding three files each is not a layout
    # anybody wants, so the size floor decides it before the ratio is read.
    files = Fixtures.layout_corpus("pkg"; sizes = fill(3, 8))
    fg = Fixtures.filegraph(files)

    @test isempty(Dendro.cluster_divisible_packages(files, fg))
    @test Dendro.read_divisible(fg, "pkg") === nothing
end

@testitem ":divisible_package stays silent on one cohesive module" setup = [Fixtures] tags = [:divisible_package] begin
    # Twenty files that all reference each other. The single group scores a perfect
    # internal ratio purely because there is nothing outside it, and a folder holding the
    # whole directory is a rename rather than a split.
    files = Fixtures.layout_corpus("pkg"; sizes = [20])
    fg = Fixtures.filegraph(files)

    @test isempty(Dendro.cluster_divisible_packages(files, fg))
    @test Dendro.read_divisible(fg, "pkg") === nothing
end

@testitem ":divisible_package abstains when most children carry no reference" setup = [Fixtures] tags = [:divisible_package] begin
    # Three clean groups buried in fifteen files that reference nothing. Those files are
    # either genuinely independent or references the resolver missed, and nothing
    # syntactic tells the two apart, so the directory is not scored rather than scored on
    # the connected part of its graph.
    files = Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8], isolated = 15)
    fg = Fixtures.filegraph(files)

    @test isempty(Dendro.cluster_divisible_packages(files, fg))
    @test Dendro.read_divisible(fg, "pkg") === nothing
end

@testitem ":divisible_package does not ask the question of a small directory" setup = [Fixtures] tags = [:divisible_package] begin
    # Two clean groups of five, eleven children in all. A directory small enough to read at
    # a glance does not want subdirectories whatever its shape.
    files = Fixtures.layout_corpus("pkg"; sizes = [5, 5], hub = true)
    fg = Fixtures.filegraph(files)
    @test length(Dendro.child_graph(fg, "pkg").names) == 11

    @test isempty(Dendro.cluster_divisible_packages(files, fg))
    @test Dendro.read_divisible(fg, "pkg") === nothing
end

@testitem ":divisible_package leaves a child every sibling reaches for out of every folder" setup = [Fixtures] tags = [:divisible_package] begin
    # Three groups of eight plus one utility every file calls. Left in, the utility pulls
    # all 24 files into one community and there is nothing to propose; dropped, the three
    # groups read cleanly and the utility stays at the top level like anything else the
    # proposal does not extract.
    files = Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8], hub = true)
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_divisible_packages(files, fg))
    @test f.value == 100
    # 25 children, 24 placed: the utility is the one left behind.
    @test first(f.locations).label == "pkg, 24 of 25 children placed"
    @test length(f.locations) == 4
end

@testitem ":divisible_package drops a child no folder could hold" setup = [Fixtures] tags = [:divisible_package] begin
    # `movable_children` is where both drops happen. A child most of the directory reaches
    # for is an artifact of cross-cutting coupling rather than a subsystem, and a file
    # naming its own directory cannot move into a subdirectory of it.
    names = ["a.rs", "b.rs", "c.rs", "d.rs", "e.rs", "lib.rs", "shared.rs"]
    adj = [Dict{Int, Float64}() for _ in names]
    link(i, j) = (adj[i][j] = 1.0; adj[j][i] = 1.0)
    link(1, 2)
    link(3, 4)
    link(1, 6)
    for i in 1:5
        link(i, 7)
    end
    cg = Dendro.ChildGraph(names, [[i] for i in eachindex(names)], adj)

    keep, sub = Dendro.movable_children(cg)
    # `shared.rs` is reached by five of the six others and `lib.rs` names the directory.
    @test [names[i] for i in keep] == ["a.rs", "b.rs", "c.rs", "d.rs", "e.rs"]
    # The renumbered subgraph carries only the edges between the children that stay, so
    # `e.rs` is left with nothing and lands in no group.
    @test sub == [Dict(2 => 1.0), Dict(1 => 1.0), Dict(4 => 1.0), Dict(3 => 1.0), Dict()]
end

@testitem ":divisible_package marks a suppressed directory rather than dropping it" setup = [Fixtures] tags = [:divisible_package] begin
    # The directive sits on the anchor file, the site the finding reports the directory at.
    files = Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8])
    anchor = findfirst(f -> f.file == "pkg/g1u1.jl", files)
    files[anchor] = Dendro.ParsedFile(
        files[anchor].profile, files[anchor].source, files[anchor].file,
        files[anchor].tree, files[anchor].index,
        [Dendro.Directive(1, Set([:divisible_package]))],
    )
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_divisible_packages(files, fg))
    @test f.suppressed
end

@testitem ":divisible_package is off by default and opts in through a config" setup = [Fixtures] tags = [:divisible_package] begin
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(joinpath(src, "pkg"))
        for f in Fixtures.layout_corpus("pkg"; sizes = [8, 8, 8])
            write(joinpath(src, f.file), f.source)
        end

        off = joinpath(dir, "off.toml")
        write(off, "[rules]\nreimplementation = false\n")
        quiet = Dendro.analyze(src; config = Fixtures.isolated_config(src, off))
        @test isempty(filter(f -> f.metric == :divisible_package, quiet))

        on = joinpath(dir, "on.toml")
        write(on, "[rules]\ndivisible_package = true\n")
        loud = Dendro.analyze(src; config = Fixtures.isolated_config(src, on))
        @test length(filter(f -> f.metric == :divisible_package, loud)) == 1
    end
end
