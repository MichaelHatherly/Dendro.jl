@testitem "file graph counts every reference across an edge" setup = [Fixtures] tags = [:file_graph] begin
    a = Fixtures.parsedfile(
        :julia,
        "include(\"b.jl\")\nuse(x) = alpha(x) + beta(x) + gamma(x) + gamma(x + 1)\n";
        file = "a.jl"
    )
    b = Fixtures.parsedfile(:julia, "alpha(y) = y\nbeta(y) = y\ngamma(y) = y\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # Three definitions referenced, one of them twice: the edge weight is the reference
    # count, not the count of distinct names, and the names are the evidence for it.
    edge = fg.edges[(fg.index["a.jl"], fg.index["b.jl"])]
    @test edge.weight == 4
    @test edge.names == ["alpha", "beta", "gamma"]
    @test edge.name_count == 3
    # The dependency is one-way: nothing in b.jl names anything in a.jl.
    @test !haskey(fg.edges, (fg.index["b.jl"], fg.index["a.jl"]))
end

@testitem "file graph splits a reference across the files it could mean" setup = [Fixtures] tags = [:file_graph] begin
    main = Fixtures.parsedfile(
        :julia,
        "include(\"b.jl\")\ninclude(\"c.jl\")\nuse(x) = helper(x) + helper(x) + only_b(x) + only_b(x)\n";
        file = "main.jl"
    )
    b = Fixtures.parsedfile(:julia, "helper(y) = y\nonly_b(y) = y\n"; file = "b.jl")
    c = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "c.jl")
    files = [main, b, c]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # `helper` names a definition in both b.jl and c.jl, so each of the two references
    # contributes a half to each edge: b.jl carries 1 from `helper` plus 2 from `only_b`,
    # c.jl carries 1. Picking one file would need a type, which is the line Dendro holds.
    @test fg.edges[(fg.index["main.jl"], fg.index["b.jl"])].weight == 3
    @test fg.edges[(fg.index["main.jl"], fg.index["c.jl"])].weight == 1
end

@testitem "a split reference survives rounding on both edges" setup = [Fixtures] tags = [:file_graph] begin
    main = Fixtures.parsedfile(
        :julia, "include(\"b.jl\")\ninclude(\"c.jl\")\nuse(x) = helper(x)\n"; file = "main.jl"
    )
    b = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "b.jl")
    c = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "c.jl")
    files = [main, b, c]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # One reference split two ways is half a reference on each edge. Rounding that to zero
    # would erase a dependency the code really has, so the count floors at one.
    @test fg.edges[(fg.index["main.jl"], fg.index["b.jl"])].weight == 1
    @test fg.edges[(fg.index["main.jl"], fg.index["c.jl"])].weight == 1
end

@testitem "file graph carries no self-edge" setup = [Fixtures] tags = [:file_graph] begin
    a = Fixtures.parsedfile(
        :julia,
        "include(\"b.jl\")\nh1(x) = x\nh2(x) = h1(x) + h1(x) + h1(x)\nuse(x) = h1(x) + h2(x) + bhelp(x)\n";
        file = "a.jl"
    )
    b = Fixtures.parsedfile(:julia, "bhelp(y) = y\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # a.jl leans on its own helpers far harder than on b.jl. Within-file coupling is what
    # `:low_cohesion` reads; here it would only swamp every node's degree.
    @test !any(k -> k[1] == k[2], keys(fg.edges))
    @test haskey(fg.edges, (fg.index["a.jl"], fg.index["b.jl"]))
end

@testitem "file graph holds a file with no edges either way" setup = [Fixtures] tags = [:file_graph] begin
    a = Fixtures.parsedfile(:julia, "include(\"b.jl\")\nuse(x) = bhelp(x)\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "bhelp(y) = y\n"; file = "b.jl")
    lonely = Fixtures.parsedfile(:julia, "# nothing to see\n"; file = "lonely.jl")
    files = [a, b, lonely]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # A file nothing references and that references nothing is a real observation, and it
    # is a denominator every corpus-relative score is measured against.
    @test fg.files == ["a.jl", "b.jl", "lonely.jl"]
    @test haskey(fg.index, "lonely.jl")
    # It holds no unit, so its representative line is the file's first.
    @test fg.first_line[fg.index["lonely.jl"]] == 1
    @test !any(k -> fg.index["lonely.jl"] in k, keys(fg.edges))
end

@testitem "file graph records the import statement admitting an edge" setup = [Fixtures] tags = [:file_graph] begin
    julia_files = [
        Fixtures.parsedfile(:julia, "\ninclude(\"b.jl\")\nuse(x) = bhelp(x)\n"; file = "a.jl"),
        Fixtures.parsedfile(:julia, "bhelp(y) = y\n"; file = "b.jl"),
    ]
    python_files = [
        Fixtures.parsedfile(:python, "def helper(x):\n    return x\n"; file = "u.py"),
        Fixtures.parsedfile(:python, "\nfrom .u import helper\ndef use(a):\n    return helper(a)\n"; file = "m.py"),
    ]
    rust_files = [
        Fixtures.parsedfile(:rust, "pub fn helper() -> i32 { 1 }\n"; file = "foo.rs"),
        Fixtures.parsedfile(:rust, "\nuse crate::foo::helper;\nfn run() -> i32 { helper() }\n"; file = "main.rs"),
    ]

    # The whole proposed edit for a dependency against the grain is "remove this import",
    # so the finding has to be able to point at the statement, in every linkage model:
    # a Julia include splice, a Python from-import, a Rust use declaration.
    for (files, from, to) in [
            (julia_files, "a.jl", "b.jl"), (python_files, "m.py", "u.py"), (rust_files, "main.rs", "foo.rs"),
        ]
        table = Dendro.corpus_symbols(files)
        corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
        fg = Dendro.build_file_graph(files, table, corpus)
        edge = fg.edges[(fg.index[from], fg.index[to])]
        @test [(l.file, l.line) for l in edge.declared] == [(from, 2)]
    end
end

@testitem "file graph draws no edge a file's linkage does not admit" setup = [Fixtures] tags = [:file_graph] begin
    a = Fixtures.parsedfile(:julia, "f(x) = helper(x)\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    # No `include` joins a.jl and b.jl, so `helper` is not a name a.jl can see. The graph
    # invents no dependency from a name coincidence.
    @test isempty(fg.edges)

    u = Fixtures.parsedfile(:python, "def helper(x):\n    return x\ndef other(y):\n    return y\n"; file = "u.py")
    m = Fixtures.parsedfile(
        :python, "from .u import helper\ndef use(a):\n    return helper(a) + other(a)\n"; file = "m.py"
    )
    pyfiles = [u, m]
    pytable = Dendro.corpus_symbols(pyfiles)
    pycorpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in pyfiles))
    pyfg = Dendro.build_file_graph(pyfiles, pytable, pycorpus)

    # The import names `helper` and not `other`, so only `helper` is evidence on the edge.
    @test pyfg.edges[(pyfg.index["m.py"], pyfg.index["u.py"])].names == ["helper"]
end

@testitem "module graph contracts files by directory" setup = [Fixtures] tags = [:file_graph] begin
    ca = Fixtures.parsedfile(:julia, "ca(x) = apihelper(x) + cb(x)\n"; file = "core/a.jl")
    cb = Fixtures.parsedfile(:julia, "cb(x) = x\n"; file = "core/b.jl")
    api = Fixtures.parsedfile(
        :julia,
        "include(\"../core/a.jl\")\ninclude(\"../core/b.jl\")\n" *
            "usec(x) = ca(x) + ca(x + 1) + cb(x) + cb(x + 1) + cb(x + 2)\napihelper(y) = y\n";
        file = "api/c.jl"
    )
    files = [ca, cb, api]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)
    mg = Dendro.module_graph(fg)

    @test mg.groups == ["api", "core"]
    @test mg.members[mg.index["core"]] == [fg.index["core/a.jl"], fg.index["core/b.jl"]]
    # api/c.jl names `ca` twice and `cb` three times, so the contracted weight sums both
    # file edges. core/a.jl names `apihelper` once, the one edge going the other way.
    @test mg.edges[(mg.index["api"], mg.index["core"])] == 5
    @test mg.edges[(mg.index["core"], mg.index["api"])] == 1
    # core/a.jl names `cb` in core/b.jl, a file edge inside one directory: contracting it
    # would make a directory depend on itself, which says nothing.
    @test !haskey(mg.edges, (mg.index["core"], mg.index["core"]))
end

@testitem "edge names are capped and the true count kept" setup = [Fixtures] tags = [:file_graph] begin
    defs = join("d$i(y) = y\n" for i in 1:12)
    a = Fixtures.parsedfile(
        :julia,
        "include(\"b.jl\")\nuse(x) = " * join(("d$i(x)" for i in 1:12), " + ") * " + d1(x) + d1(x)\n";
        file = "a.jl"
    )
    b = Fixtures.parsedfile(:julia, defs; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
    fg = Dendro.build_file_graph(files, table, corpus)

    edge = fg.edges[(fg.index["a.jl"], fg.index["b.jl"])]
    # A hot edge can name hundreds of definitions. The list is capped at the heaviest few
    # and says how many there really are, so a truncated list never reads as complete.
    @test length(edge.names) == Dendro.EDGE_NAMES_MAX
    @test edge.name_count == 12
    @test "d1" in edge.names
    @test issorted(edge.names)
    @test edge.weight == 14
end

@testitem "file graph is identical across thread counts" tags = [:file_graph] begin
    mktempdir() do dir
        # More than PARALLEL_MIN files, chained so every file resolves a reference into
        # another, with one name defined twice so the split weighting does real work.
        for i in 1:16
            body = i == 1 ? "g1(x) = shared(x)\n" : "g$i(x) = g$(i - 1)(x) + shared(x) + $i\n"
            write(joinpath(dir, "f$i.jl"), body)
        end
        write(joinpath(dir, "f1.jl"), "g1(x) = shared(x)\nshared(y) = y\n")
        write(joinpath(dir, "f2.jl"), "g2(x) = g1(x) + shared(x)\nshared(y) = y + 1\n")
        write(joinpath(dir, "mod.jl"), join("include(\"f$i.jl\")\n" for i in 1:16))

        # A byte-identical serialisation is the guarantee: no Dict iteration order may
        # reach the file list, an edge's evidence, or the contracted module graph.
        script = raw"""
        import Dendro
        function digest(fg)
            io = IOBuffer()
            for p in fg.files
                print(io, basename(p), ':', fg.first_line[fg.index[p]], ';')
            end
            for k in sort!(collect(keys(fg.edges)))
                e = fg.edges[k]
                print(io, basename(fg.files[k[1]]), "->", basename(fg.files[k[2]]))
                print(io, '|', e.weight, '|', join(e.names, ','), '|', e.name_count, '|')
                for l in e.declared
                    print(io, basename(l.file), ':', l.line, ',')
                end
                print(io, ';')
            end
            mg = Dendro.module_graph(fg)
            for k in sort!(collect(keys(mg.edges)))
                print(io, mg.groups[k[1]], "=>", mg.groups[k[2]], '|', mg.edges[k], ';')
            end
            return String(take!(io))
        end
        files = Dendro.parse_corpus(Dendro.source_files(ARGS[1]))
        table = Dendro.corpus_symbols(files)
        corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
        fg = Dendro.build_file_graph(files, table, corpus)
        print(digest(fg), '|', length(fg.edges))
        """

        # `--startup-file=no` pins the captured stdout, as the analyze determinism item does.
        proj = Base.active_project()
        runs = [
            read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t$t -e $script $dir`, String)
                for t in (1, 2, 4)
        ]

        @test runs[1] == runs[2]
        @test runs[1] == runs[3]
        # The corpus is built to produce edges, so a match on an empty graph is no proof.
        @test parse(Int, split(runs[1], '|')[end]) > 0
    end
end
