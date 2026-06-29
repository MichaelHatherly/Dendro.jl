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
    Dendro.mermaid_coupling(io, files, graph, table, :unit, 0.95)
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
    Dendro.mermaid_coupling(io, files, graph, table, :file, 0.95)
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
    Dendro.mermaid_reachability(io, [a], table, :unit)
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
