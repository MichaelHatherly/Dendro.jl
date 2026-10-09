# The per-file line count. Every item passes its own band, so a fixture stays a few lines
# long rather than carrying the hundreds the shipped band is set at.

@testitem "cluster_file_length flags the long file among short ones" setup = [Fixtures] tags = [:file_length] begin
    files = [Fixtures.linefile(n) for n in [2, 3, 4, 5, 6, 20]]
    hit = only(Dendro.cluster_file_length(files; band = (10, 30)))
    @test hit.metric == :file_length
    @test hit.kind == :scalar
    @test hit.value == 20
    @test hit.absolute == :warn
    @test [(l.file, l.line, l.unit) for l in hit.locations] == [("f20.jl", 1, "")]
end

@testitem "cluster_file_length reads a file ending mid-line as a whole one" setup = [Fixtures] tags = [:file_length] begin
    # The source a scan reads is whatever the file holds, so the last line of a file saved
    # without a trailing newline has to count like any other.
    src = join(["f$i(x) = x" for i in 1:20], "\n")
    closed = Fixtures.parsedfile(:julia, src * "\n"; file = "closed.jl")
    open = Fixtures.parsedfile(:julia, src; file = "open.jl")
    hits = Dendro.cluster_file_length([closed, open]; band = (10, 30))
    @test [f.value for f in hits] == [20, 20]
end

@testitem "cluster_file_length withholds the percentile on a thin corpus" setup = [Fixtures] tags = [:file_length] begin
    files = [Fixtures.linefile(n) for n in [2, 3, 4, 20]]
    # Four files is under the floor, so the rank says nothing and only the band fires.
    hit = only(Dendro.cluster_file_length(files; band = (10, 30)))
    @test hit.value == 20
    @test hit.percentile === nothing
    @test isempty(Dendro.cluster_file_length(files; band = (100, 200)))
end

@testitem "cluster_file_length respects dendro-ignore-file" setup = [Fixtures] tags = [:file_length] begin
    src = "# dendro-ignore-file: file_length\n" * join(["f$i(x) = x" for i in 1:19], "\n") * "\n"
    i = Fixtures.idx(:julia, src)
    directives = Dendro.suppressions(i; file = "f.jl")
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl", directives = directives)]
    hit = only(Dendro.cluster_file_length(files; band = (10, 30)))
    @test hit.value == 20
    @test hit.suppressed
end

@testitem "a file_length finding survives a diff scope only on line 1" setup = [Fixtures] tags = [:file_length] begin
    # The finding's one location is line 1, so a spatial `base` scope keeps it only where
    # the change reaches that line. An edit in the middle of a long file does not
    # re-report its length, which is what the `--since` ratchet is the surface for.
    mktempdir() do dir
        path = joinpath(dir, "f.jl")
        write(path, join(["f$i(x) = x" for i in 1:20], "\n") * "\n")
        files = Dendro.parse_corpus([path])
        hits = Dendro.cluster_file_length(files; band = (10, 30))
        @test only(only(hits).locations).line == 1

        middle = Dendro.Scope(realpath(dir), Dict("f.jl" => [10:12]), files)
        @test isempty(Dendro.scope_clusters(hits, middle))
        head = Dendro.Scope(realpath(dir), Dict("f.jl" => [1:2]), files)
        @test length(Dendro.scope_clusters(hits, head)) == 1
    end
end

@testitem "analyze reports file_length by default" setup = [Fixtures] tags = [:file_length] begin
    # The pass runs with no configuration, the half `cluster_file_length` alone cannot show.
    mktempdir() do dir
        for n in [2, 3, 4, 5, 6, 20]
            write(joinpath(dir, "f$n.jl"), join(["f$i(x) = x" for i in 1:n], "\n") * "\n")
        end
        cfg = Dendro.Config(; file_length = (10, 30))
        hits = filter(f -> f.metric == :file_length, Dendro.analyze(dir; config = cfg))
        @test [basename(only(f.locations).file) for f in hits] == ["f20.jl"]
    end
end
