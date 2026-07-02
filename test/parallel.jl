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
        fs = Dendro.analyze(ARGS[1])
        print(hash(digest(fs)), '|', length(fs))
        """

        # `--startup-file=no` pins the captured stdout: `julia_cmd` propagates the flag only
        # when the host was started with it, and a printing startup.jl would break the diff.
        proj = Base.active_project()
        serial = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t1 -e $script $dir`, String)
        parallel = read(`$(Base.julia_cmd()) --startup-file=no --project=$proj -t4 -e $script $dir`, String)

        @test serial == parallel
        # The corpus is built to produce findings, so a match on an empty result is no proof.
        @test parse(Int, split(serial, '|')[2]) > 0
    end
end
