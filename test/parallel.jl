@testitem "chunk_indices partitions 1:n exactly once" tags = [:parallel] begin
    for (n, nc) in [(10, 3), (8, 4), (1, 1), (20, 8), (7, 7)]
        chunks = Dendro.chunk_indices(n, nc)
        @test length(chunks) == nc
        @test sort(reduce(vcat, chunks; init = Int[])) == collect(1:n)
        # Round-robin: chunk sizes differ by at most one.
        @test maximum(length, chunks) - minimum(length, chunks) <= 1
    end
end

@testitem "a failed fan-out task rethrows its own exception" tags = [:parallel] begin
    chunks = Dendro.chunk_indices(8, 2)
    @test_throws ArgumentError Dendro.spawn_chunks((c, idxs) -> throw(ArgumentError("boom")), chunks)
end

@testitem "merge_baselines matches serial sampling" setup = [Fixtures] tags = [:parallel] begin
    files = [Fixtures.parsedfile(:julia, Fixtures.chain("f$i", 4 + i % 5)) for i in 1:12]

    serial = Dendro.Baseline()
    for f in files
        Dendro.add_samples!(serial, f.index)
    end
    for v in values(serial.samples)
        sort!(v)
    end

    parts = [Dendro.Baseline() for _ in 1:3]
    for (i, f) in enumerate(files)
        Dendro.add_samples!(parts[mod1(i, 3)], f.index)
    end
    merged = Dendro.merge_baselines(parts)
    for v in values(merged.samples)
        sort!(v)
    end

    @test merged.samples == serial.samples
end

@testitem "analyze is deterministic across thread counts" tags = [:parallel] begin
    mktempdir() do dir
        # More than PARALLEL_MIN files, seeded with exact clones and near-misses so the
        # parallel duplicate, linkage, and scoring passes all do real work.
        for i in 1:24
            n = 6 + (i % 5)
            extra = i % 3 == 0 ? "    z = z * 2\n" : ""
            body = join("    a$k = z + $k\n" for k in 1:n)
            write(joinpath(dir, "f$i.jl"), "function f$i(z)\n" * body * extra * "    return z\nend\n")
        end

        # A layered pair of directories on the side, api leaning on core with one reference
        # running back, so the cross-file graph passes have a grain to read as well.
        mkpath(joinpath(dir, "core"))
        mkpath(joinpath(dir, "api"))
        # One function duplicated across those two directories, longer than anything in the
        # flat set so it clones only its own copy. It sits at a wider module distance than
        # the flat clones, so the clone re-rank has an ordering to decide rather than a
        # constant to sort by.
        chain(name) = string(
            "function $name($(name)0)\n",
            join("    $name$i = $name$(i - 1) + $i\n" for i in 1:16),
            "    return $name$(16)\nend\n"
        )
        write(joinpath(dir, "core", "c.jl"), "core_a(x) = x\nbackc(x) = apihelp(x)\n" * chain("dupc"))
        write(
            joinpath(dir, "api", "a.jl"),
            "apihelp(y) = y\nusea(x) = " * join(("core_a(x)" for _ in 1:20), " + ") * "\n" * chain("dupa")
        )
        write(joinpath(dir, "layered.jl"), "include(\"core/c.jl\")\ninclude(\"api/a.jl\")\n")

        # The digest keeps findings and locations in returned order: the guarantee under
        # test is byte-identical output, ordering included, at any thread count.
        script = raw"""
        import Dendro
        function digest(fs)
            lines = String[]
            for f in fs
                io = IOBuffer()
                print(io, f.metric, '|', f.value, '|', f.absolute, '|', f.percentile, '|', f.suppressed, '|')
                for x in f.locations
                    print(io, basename(x.file), ':', x.line, ':', x.unit, ';')
                end
                push!(lines, String(take!(io)))
            end
            return join(lines, '\n')
        end
        spans(f) = f.metric === :duplicate &&
            length(Set(basename(dirname(x.file)) for x in f.locations)) > 1
        fs = Dendro.analyze(ARGS[1])
        print(
            hash(digest(fs)), '|', length(fs), '|', count(f -> f.metric === :back_edge, fs),
            '|', count(spans, fs)
        )
        """

        # `--startup-file=no` pins the captured stdout: `julia_cmd` propagates the flag only
        # when the host was started with it, and a printing startup.jl would break the diff.
        proj = Base.active_project()
        serial = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t1 -e $script $dir`, String)
        parallel = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t4 -e $script $dir`, String)

        @test serial == parallel
        # The corpus is built to produce findings, so a match on an empty result is no proof.
        @test parse(Int, split(serial, '|')[2]) > 0
        # The layered directories are here to put the file-graph pass in the digest. The
        # count above is satisfied by the clone files alone, so without this the coverage
        # could vanish and the item would stay green.
        @test parse(Int, split(serial, '|')[3]) > 0
        # Same guard for the clone re-rank: the flat clones all share one directory, so
        # without a cross-directory clone the ranking pass would sort a constant.
        @test parse(Int, split(serial, '|')[4]) > 0
    end
end

@testitem "the hub pass is deterministic across thread counts" tags = [:parallel] begin
    mktempdir() do dir
        # Two interleaved chains: `a$i` reaches three files back, `b$i` six back, so every
        # middle file both depends on six others and is depended on by six, and its two
        # audiences share no consumer. That exercises the crossing score and the audience
        # split together.
        for i in 1:24
            back(offsets, prefix) = join(("$prefix$(i - k)(x)" for k in offsets if i - k >= 1), " + ")
            a = back(1:3, "a")
            b = back(4:6, "b")
            write(joinpath(dir, "f$i.jl"), "a$i(x) = $(isempty(a) ? "x" : a)\nb$i(x) = $(isempty(b) ? "x" : b)\n")
        end
        write(joinpath(dir, "mod.jl"), join("include(\"f$i.jl\")\n" for i in 1:24))

        # Byte-identical findings are the guarantee: no Dict iteration order may reach the
        # crossing scores, the audience groups, or the representative each one reports.
        script = raw"""
        import Dendro
        files = Dendro.parse_corpus(Dendro.source_files(ARGS[1]))
        table = Dendro.corpus_symbols(files)
        visible = Dendro.corpus_visibility(files, table)
        corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
        fg = Dendro.build_file_graph(files, table, corpus; visible)
        fs = Dendro.cluster_hub(files, fg, table; visible, band = (2, 3), min_files = 10)
        io = IOBuffer()
        for f in fs
            print(io, f.value, '|', f.absolute, '|', f.percentile, '|', f.suppressed, '|')
            for l in f.locations
                print(io, basename(l.file), ':', l.line, ':', l.unit, ';')
            end
            print(io, '\n')
        end
        print(String(take!(io)), '|', length(fs))
        """

        # `--startup-file=no` pins the captured stdout, as the analyze determinism item does.
        proj = Base.active_project()
        runs = [
            read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t$t -e $script $dir`, String)
                for t in (1, 2, 4, 8)
        ]

        @test runs[1] == runs[2]
        @test runs[1] == runs[3]
        @test runs[1] == runs[4]
        # The corpus is built to produce hubs, so a match on an empty result is no proof.
        @test parse(Int, split(runs[1], '|')[end]) > 0
    end
end

@testitem "the file graph is deterministic across thread counts" tags = [:parallel] begin
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
                for t in (1, 2, 4, 8)
        ]

        @test runs[1] == runs[2]
        @test runs[1] == runs[3]
        @test runs[1] == runs[4]
        # The corpus is built to produce edges, so a match on an empty graph is no proof.
        @test parse(Int, split(runs[1], '|')[end]) > 0
    end
end

@testitem "the incoherent package pass is deterministic across thread counts" tags = [:parallel] begin
    mktempdir() do dir
        # Two packages of four files each, every file coupled to a different one of four
        # other directories, so both packages belong wholly elsewhere. Thirteen files in
        # total, more than PARALLEL_MIN.
        homes = ("a", "b", "c", "d")
        for h in homes
            mkpath(joinpath(dir, h))
            write(joinpath(dir, h, "$h.jl"), "$(h)y() = $(h)z()\n$(h)z() = $(h)y()\n")
        end
        for pkg in ("pkg", "lib")
            mkpath(joinpath(dir, pkg))
            for (i, h) in enumerate(homes)
                write(joinpath(dir, pkg, "f$i.jl"), "$(pkg)$i() = $(h)y() + $(h)z()\n")
            end
        end
        write(
            joinpath(dir, "mod.jl"),
            join("include(\"$h/$h.jl\")\n" for h in homes) *
                join("include(\"$pkg/f$i.jl\")\n" for pkg in ("pkg", "lib") for i in 1:4)
        )

        # A byte-identical serialisation is the guarantee: neither the communities, the
        # directory grouping, nor the representative pairs may follow a Dict's iteration
        # order.
        script = raw"""
        import Dendro
        function digest(fs)
            io = IOBuffer()
            for f in fs
                print(io, f.metric, '|', f.value, '|', f.absolute, '|', f.percentile, '|')
                for l in f.locations
                    print(io, basename(dirname(l.file)), '/', basename(l.file), ':', l.line, ':', l.unit, ';')
                end
                print(io, '\n')
            end
            return String(take!(io))
        end
        files = Dendro.parse_corpus(Dendro.source_files(ARGS[1]))
        table = Dendro.corpus_symbols(files)
        graph = Dendro.build_corpus_graph(files, table)
        fs = Dendro.cluster_incoherent_packages(files, graph)
        print(digest(fs), '|', length(fs))
        """

        # `--startup-file=no` pins the captured stdout, as the analyze determinism item does.
        proj = Base.active_project()
        runs = [
            read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t$t -e $script $dir`, String)
                for t in (1, 2, 4, 8)
        ]

        @test runs[1] == runs[2]
        @test runs[1] == runs[3]
        @test runs[1] == runs[4]
        # Two packages are planted, so a match on an empty result is no proof.
        @test parse(Int, split(runs[1], '|')[end]) == 2
    end
end

@testitem "the dependency cycle pass is deterministic across thread counts" tags = [:parallel] begin
    mktempdir() do dir
        # A fourteen-file ring plus a disjoint pair, more than PARALLEL_MIN files in total.
        # The reference counts vary around the ring, so the weighted arrangement has a real
        # choice to make about which edge it proposes cutting.
        for i in 1:14
            nxt = i == 14 ? 1 : i + 1
            refs = join(("g$nxt(x + $k)" for k in 1:(1 + i % 3)), " + ")
            write(joinpath(dir, "r$i.jl"), "include(\"r$nxt.jl\")\nf$i(x) = $refs\ng$i(y) = y\n")
        end
        write(joinpath(dir, "p1.jl"), "include(\"p2.jl\")\nfp1(x) = gp2(x)\ngp1(y) = y\n")
        write(joinpath(dir, "p2.jl"), "include(\"p1.jl\")\nfp2(x) = gp1(x)\ngp2(y) = y\n")

        # A byte-identical serialisation is the guarantee: neither the components Tarjan
        # closes, the arrangement the heuristic builds, nor the locations it reports may
        # follow a Dict's iteration order.
        script = raw"""
        import Dendro
        function digest(fs)
            io = IOBuffer()
            for f in fs
                print(io, f.metric, '|', f.value, '|', f.absolute, '|', f.percentile, '|')
                for l in f.locations
                    print(io, basename(l.file), ':', l.line, ':', l.unit, ';')
                end
                print(io, '\n')
            end
            return String(take!(io))
        end
        files = Dendro.parse_corpus(Dendro.source_files(ARGS[1]))
        table = Dendro.corpus_symbols(files)
        corpus = Dendro.Corpus(Set{String}(Dendro.to_posix(f.file) for f in files))
        fg = Dendro.build_file_graph(files, table, corpus)
        fs = Dendro.cluster_dependency_cycles(files, fg; band = (2, 4))
        print(digest(fs), '|', length(fs))
        """

        # `--startup-file=no` pins the captured stdout, as the analyze determinism item does.
        proj = Base.active_project()
        runs = [
            read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t$t -e $script $dir`, String)
                for t in (1, 2, 4, 8)
        ]

        @test runs[1] == runs[2]
        @test runs[1] == runs[3]
        @test runs[1] == runs[4]
        # Two components are planted, so a match on an empty result is no proof.
        @test parse(Int, split(runs[1], '|')[end]) == 2
    end
end

@testitem ":split_audience is deterministic across thread counts" tags = [:parallel] begin
    mktempdir() do dir
        # Six provider files, each read by two consumers that share no definition, over
        # enough files to clear the fan-out floor in the reference resolution the pass
        # reads. Every provider splits into two audiences.
        includes = String[]
        for i in 1:6
            write(joinpath(dir, "p$i.jl"), "pa$i() = 1\npb$i() = 2\npc$i() = 3\npd$i() = 4\n")
            write(joinpath(dir, "x$i.jl"), "x$i() = pa$i() + pb$i()\n")
            write(joinpath(dir, "y$i.jl"), "y$i() = pc$i() + pd$i()\n")
            append!(includes, ["include(\"p$i.jl\")", "include(\"x$i.jl\")", "include(\"y$i.jl\")"])
        end
        write(joinpath(dir, "mod.jl"), join(includes, "\n") * "\n")

        # The digest keeps the audience findings and their locations in returned order:
        # the guarantee under test is byte-identical output at any thread count.
        script = raw"""
        import Dendro
        fs = filter(f -> f.metric === :split_audience, Dendro.analyze(ARGS[1]; cut = 0.5))
        io = IOBuffer()
        for f in fs
            print(io, f.value, '|', f.absolute, '|')
            for x in f.locations
                print(io, basename(x.file), ':', x.line, ':', x.unit, ';')
            end
            print(io, '\n')
        end
        print(hash(String(take!(io))), '|', length(fs))
        """

        proj = Base.active_project()
        serial = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t1 -e $script $dir`, String)
        parallel = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t4 -e $script $dir`, String)

        @test serial == parallel
        # A match on an empty result would prove nothing: the corpus is built to split.
        @test parse(Int, split(serial, '|')[2]) == 6
    end
end
