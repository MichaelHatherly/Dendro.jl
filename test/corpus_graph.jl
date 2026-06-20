@testitem "corpus graph resolves a cross-file call through an include splice" setup = [Fixtures] tags = [:corpus_graph] begin
    main = Fixtures.parsedfile(:julia, "include(\"util.jl\")\nf(x) = helper(x) + 1\n"; file = "main.jl")
    util = Fixtures.parsedfile(:julia, "helper(y) = y * 2\n"; file = "util.jl")
    files = [main, util]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `f` in main.jl calls `helper`, defined in util.jl, which main.jl splices in via
    # `include`. The reference resolves across the file boundary to helper's unit, the
    # whole point of the corpus graph.
    fidx = graph.unit_index[("main.jl", 1)]
    hidx = graph.unit_index[("util.jl", 1)]
    @test haskey(graph.edges, (fidx, hidx))
    @test graph.edges[(fidx, hidx)] ≈ 1.0
    # The placement signal: all of f's cross-file reference mass lands in util.jl.
    @test graph.file_mass[fidx]["util.jl"] ≈ 1.0
    # f and helper couple, so community detection puts them together.
    comm = Dendro.communities(graph)
    @test comm[fidx] == comm[hidx]
end

@testitem "corpus graph leaves files with no include link unconnected" setup = [Fixtures] tags = [:corpus_graph] begin
    a = Fixtures.parsedfile(:julia, "f(x) = helper(x)\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # No `include` connects a.jl and b.jl, so `helper` is not visible across the
    # boundary. The reference stays unresolved: no cross-file edge, no invented link.
    @test isempty(graph.edges)
end

@testitem "corpus graph resolves a Python from-import across files" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:python, "def helper(x):\n    return x\n"; file = "pkg/util.py")
    main = Fixtures.parsedfile(:python, "from .util import helper\ndef use(a):\n    return helper(a)\n"; file = "pkg/main.py")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use` in main.py calls `helper`, brought into scope by `from .util import helper`.
    # The relative import resolves to pkg/util.py, so the reference crosses the file
    # boundary to helper's unit.
    uidx = graph.unit_index[("pkg/main.py", 1)]
    hidx = graph.unit_index[("pkg/util.py", 1)]
    @test haskey(graph.edges, (uidx, hidx))
    @test graph.file_mass[uidx]["pkg/util.py"] ≈ 1.0
end

@testitem "corpus graph honours a Python import's name list" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:python, "def helper(x):\n    return x\ndef other(y):\n    return y\n"; file = "u.py")
    # `main` imports only `helper`; its call to `other` is not in scope, so it stays
    # unresolved. The import list gates visibility, name by name.
    main = Fixtures.parsedfile(:python, "from .u import helper\ndef use(a):\n    return helper(a) + other(a)\n"; file = "m.py")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    uidx = graph.unit_index[("m.py", 1)]
    helper_idx = graph.unit_index[("u.py", 1)]
    other_idx = graph.unit_index[("u.py", 2)]
    @test haskey(graph.edges, (uidx, helper_idx))
    @test !haskey(graph.edges, (uidx, other_idx))
end

@testitem "corpus graph resolves a real cross-file edge in Dendro's own source" tags = [:corpus_graph] begin
    src = joinpath(pkgdir(Dendro), "src")
    files = Dendro.parse_corpus(Dendro.source_files(src))
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # corpus.jl calls `cluster_low_cohesion`, defined in cohesion.jl. The include splice
    # in Dendro.jl puts both files in one module, so the call resolves across files. The
    # realistic integration test for Julia splice resolution.
    found = any(graph.edges) do ((s, d), _)
        endswith(graph.units[s].file, "corpus.jl") && endswith(graph.units[d].file, "cohesion.jl")
    end
    @test found
end
