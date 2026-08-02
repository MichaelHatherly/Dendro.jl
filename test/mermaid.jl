# Mermaid diagram export. Each item builds a tiny corpus, renders one graph, and asserts
# the diagram carries the expected nodes, edges, and overlay classes. The renderers take
# the built structures directly, the shape the public `mermaid` wraps with a parse pass.

@testitem "mermaid coupling unit-level draws cross-file edges and communities" setup = [Fixtures] tags = [:mermaid] begin
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = shared()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "shared() = 1\n"; file = "b.jl")
    files = [mod, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    io = IOBuffer()
    Dendro.mermaid_coupling(io, files, graph, table, :unit, 0.95, :all, 1)
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test occursin("entry", out)
    @test occursin("shared", out)
    @test occursin("-->", out)
    @test occursin("subgraph community", out)
end

@testitem "mermaid coupling file-level collapses units to files" setup = [Fixtures] tags = [:mermaid] begin
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = shared()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "shared() = 1\n"; file = "b.jl")
    files = [mod, a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    io = IOBuffer()
    Dendro.mermaid_coupling(io, files, graph, table, :file, 0.95, :all, 1)
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test occursin("a.jl", out)
    @test occursin("b.jl", out)
    @test occursin("-->", out)
end

@testitem "mermaid reachability flags dead defs and marks roots" setup = [Fixtures] tags = [:mermaid] begin
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = 1\ndead() = 2\n"; file = "a.jl")
    table = Dendro.corpus_symbols([a])
    io = IOBuffer()
    Dendro.mermaid_reachability(io, [a], table, :unit, :all, 1)
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test occursin("dead", out)
    @test occursin("keep", out)
    @test occursin(r"^  class \w+ dead$"m, out)
    @test occursin(r"^  class \w+ root$"m, out)
end

@testitem "mermaid clones group duplicated functions into a cluster" setup = [Fixtures] tags = [:mermaid] begin
    a = Fixtures.parsedfile(:julia, Fixtures.chain("foo", 11); file = "a.jl")
    b = Fixtures.parsedfile(:julia, Fixtures.chain("bar", 11); file = "b.jl")
    io = IOBuffer()
    Dendro.mermaid_clones(io, [a, b], :unit, Dendro.DEFAULT_MIN_SIZE, Dendro.DEFAULT_THRESHOLD, Dendro.DEFAULT_RADIUS_FACTOR)
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test occursin("subgraph clone_", out)
    @test occursin("foo", out)
    @test occursin("bar", out)
end

@testitem "mermaid reachability focus keeps dead defs and one hop of context" setup = [Fixtures] tags = [:mermaid] begin
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = util()\nutil() = 1\ndead() = util()\n"; file = "a.jl")
    table = Dendro.corpus_symbols([a])
    io = IOBuffer()
    Dendro.mermaid_reachability(io, [a], table, :unit, :findings, 1)
    out = String(take!(io))
    @test occursin("dead", out)
    @test occursin("util", out)
    @test occursin(r"^  class \w+ dead$"m, out)
    @test occursin(r"^  class \w+ context$"m, out)
    @test !occursin("keep", out)
end

@testitem "mermaid reachability focus with no context keeps only the finding" setup = [Fixtures] tags = [:mermaid] begin
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = util()\nutil() = 1\ndead() = util()\n"; file = "a.jl")
    table = Dendro.corpus_symbols([a])
    io = IOBuffer()
    Dendro.mermaid_reachability(io, [a], table, :unit, :findings, 0)
    out = String(take!(io))
    @test occursin("dead", out)
    @test !occursin("util", out)
    @test !occursin(r"^  class \w+ context$"m, out)
end

@testitem "mermaid coupling focus drops nodes when nothing is flagged" setup = [Fixtures] tags = [:mermaid] begin
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = shared()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "shared() = 1\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)
    io = IOBuffer()
    Dendro.mermaid_coupling(io, files, graph, table, :unit, 0.95, :findings, 1)
    @test !occursin("subgraph community", String(take!(io)))
    Dendro.mermaid_coupling(io, files, graph, table, :unit, 0.95, :all, 1)
    @test occursin("subgraph community", String(take!(io)))
end

@testitem "mermaid focus defaults on at unit granularity, off at file" setup = [Fixtures] tags = [:mermaid] begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "export keep\nkeep() = util()\nutil() = 1\ndead() = util()\n")
        io = IOBuffer()
        Dendro.mermaid(io, dir; graph = :reachability, granularity = :unit)
        @test !occursin("keep", String(take!(io)))
        Dendro.mermaid(io, dir; graph = :reachability, granularity = :unit, focus = :all)
        @test occursin("keep", String(take!(io)))
    end
end

@testitem "mermaid public entrypoint validates focus and context" tags = [:mermaid] begin
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; focus = :nope)
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; context = -1)
end

@testitem "mermaid escapes a quote in a node label" setup = [Fixtures] tags = [:mermaid] begin
    @test Dendro.mmd_label("a\"b") == "a#quot;b"
    @test Dendro.mmd_label("one\ntwo") == "one two"
end

@testitem "mermaid public entrypoint validates graph and granularity" tags = [:mermaid] begin
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; graph = :nope)
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; granularity = :nope)
end

@testitem "mermaid renders an empty corpus as a valid diagram" tags = [:mermaid] begin
    mktempdir() do dir
        io = IOBuffer()
        Dendro.mermaid(io, dir; graph = :coupling)
        @test startswith(String(take!(io)), "flowchart LR")
    end
end

# The change view: the file graph at a base ref against the file graph at the working
# tree. Only the edges whose weight moved are drawn, with the state carried by the arrow.

@testitem "change deltas report an added, dropped, and reweighted edge" tags = [:mermaid] begin
    edge(w, names) = Dendro.FileEdge(w, names, length(names), Dendro.Location[])
    base = Dict(("a.jl", "b.jl") => edge(3, ["old"]), ("a.jl", "c.jl") => edge(2, ["gone"]), ("b.jl", "c.jl") => edge(1, ["same"]))
    head = Dict(("a.jl", "b.jl") => edge(5, ["old", "fresh"]), ("d.jl", "b.jl") => edge(1, ["born"]), ("b.jl", "c.jl") => edge(1, ["same"]))

    deltas = Dendro.change_deltas(base, head)
    # The unchanged edge is absent: a diagram of everything is the coupling view.
    @test [(d.from, d.to) for d in deltas] == [("a.jl", "b.jl"), ("a.jl", "c.jl"), ("d.jl", "b.jl")]
    @test [(d.base, d.head) for d in deltas] == [(3, 5), (2, 0), (0, 1)]
    # Only the names the edge gained, so a thickened edge says what arrived on it.
    @test deltas[1].names == ["fresh"]
    @test deltas[3].names == ["born"]
end

@testitem "change view draws growth thick and shrinkage dotted" tags = [:mermaid] begin
    deltas = [
        Dendro.EdgeDelta("a.jl", "b.jl", 0, 2, ["born"]),
        Dendro.EdgeDelta("a.jl", "c.jl", 3, 5, ["fresh"]),
        Dendro.EdgeDelta("b.jl", "c.jl", 4, 1, String[]),
        Dendro.EdgeDelta("c.jl", "d.jl", 2, 0, String[]),
    ]
    io = IOBuffer()
    Dendro.change_file(io, deltas)
    out = String(take!(io))

    @test startswith(out, "flowchart LR")
    @test occursin("==>|new: born|", out)
    @test occursin("==>|+2 fresh|", out)
    @test occursin("-.->|-3|", out)
    @test occursin("-.->|gone|", out)
end

@testitem "change view reports a reference that crossed a new file boundary" setup = [Fixtures] tags = [:mermaid] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "mod.jl"), "include(\"a.jl\")\ninclude(\"b.jl\")\n")
    write(joinpath(src, "a.jl"), "export entry\nentry() = 1\n")
    write(joinpath(src, "b.jl"), "export shared\nshared() = 1\n")
    Fixtures.commit!(root, "base")
    # `entry` now reaches into `b.jl`, which is one new file-graph edge.
    write(joinpath(src, "a.jl"), "export entry\nentry() = shared()\n")

    io = IOBuffer()
    Dendro.mermaid(io, src; graph = :change, base = "HEAD")
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test occursin("==>", out)
    @test occursin("new: shared", out)
    @test occursin("a.jl", out)
    @test occursin("b.jl", out)
end

@testitem "change view draws nothing when the corpus is untouched" setup = [Fixtures] tags = [:mermaid] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "mod.jl"), "include(\"a.jl\")\ninclude(\"b.jl\")\n")
    write(joinpath(src, "a.jl"), "export entry\nentry() = shared()\n")
    write(joinpath(src, "b.jl"), "export shared\nshared() = 1\n")
    Fixtures.commit!(root, "base")

    io = IOBuffer()
    Dendro.mermaid(io, src; graph = :change, base = "HEAD")
    out = String(take!(io))
    @test startswith(out, "flowchart LR")
    @test !occursin("==>", out)
    @test !occursin("-.->", out)
end

@testitem "change view requires a base ref and rejects unit granularity" tags = [:mermaid] begin
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; graph = :change)
    @test_throws ErrorException Dendro.mermaid(IOBuffer(), "src"; graph = :change, base = "HEAD", granularity = :unit)
end

@testitem "mermaid public entrypoint runs end to end on a folder" setup = [Fixtures] tags = [:mermaid] begin
    mktempdir() do dir
        write(joinpath(dir, "mod.jl"), "include(\"a.jl\")\ninclude(\"b.jl\")\n")
        write(joinpath(dir, "a.jl"), "export entry\nentry() = shared()\n")
        write(joinpath(dir, "b.jl"), "shared() = 1\n")
        for g in (:coupling, :reachability, :clones), gr in (:file, :unit)
            io = IOBuffer()
            Dendro.mermaid(io, dir; graph = g, granularity = gr)
            @test startswith(String(take!(io)), "flowchart LR")
        end
    end
end
