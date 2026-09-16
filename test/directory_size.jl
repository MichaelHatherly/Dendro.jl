@testitem ":child_count fires on a directory holding too many children" setup = [Fixtures] tags = [:child_count] begin
    # Twelve files in one directory beside three in another. Nothing about the coupling
    # separates the two, and the coupling is what every other directory rule reads: the
    # count is the whole reading here.
    files = [
        Fixtures.layout_corpus("wide"; sizes = [12], mod = "wide.jl")
        Fixtures.layout_corpus("narrow"; sizes = [3], mod = "narrow.jl")
    ]
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_child_count(files, fg; band = (10, 20)))
    @test f.metric == :child_count
    @test f.kind == :scalar
    @test f.value == 12
    @test f.absolute == :warn
    # Two scored directories, too few to rank against, so only the absolute band fires.
    @test f.percentile === nothing
end

@testitem ":child_count counts a subdirectory as one child" setup = [Fixtures] tags = [:child_count] begin
    # Five subdirectories of two files each. The parent holds five children rather than
    # ten: a grandchild counts toward the directory holding it and toward no directory
    # above that one.
    files = [
        Fixtures.parsedfile(:julia, "f$(g)$(u)(x) = x\n"; file = "pkg/g$g/u$u.jl")
            for g in 1:5 for u in 1:2
    ]
    fg = Fixtures.filegraph(files)

    findings = Dendro.cluster_child_count(files, fg; band = (2, 20), min_dirs = 10)
    @test [(first(f.locations).file, f.value) for f in findings] == [
        ("pkg/g1/u1.jl", 5),
        ("pkg/g1/u1.jl", 2),
        ("pkg/g2/u1.jl", 2),
        ("pkg/g3/u1.jl", 2),
        ("pkg/g4/u1.jl", 2),
        ("pkg/g5/u1.jl", 2),
    ]
end

@testitem ":child_count reports a directory at the earliest file it holds" setup = [Fixtures] tags = [:child_count] begin
    # A directory of two files and one subdirectory. The finding points at code, never at
    # the directory's own path, so the site is the earliest file the directory holds, at
    # that file's first unit. Everything the score leaves out, the split between files and
    # subdirectories and the lines they hold, rides in the label.
    files = [
        Fixtures.parsedfile(:julia, "# a header\nf1(x) = x\n"; file = "pkg/a/deep.jl"),
        Fixtures.parsedfile(:julia, "f2(x) = x\n"; file = "pkg/b.jl"),
        Fixtures.parsedfile(:julia, "f3(x) = x\n"; file = "pkg/c.jl"),
    ]
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_child_count(files, fg; band = (3, 20), min_dirs = 10))
    loc = only(f.locations)
    @test (loc.file, loc.line, loc.unit) == ("pkg/a/deep.jl", 2, "")
    @test loc.label == "pkg, 2 files, 1 subdirectories, 4 lines"
end

@testitem ":child_count marks a suppressed directory rather than dropping it" setup = [Fixtures] tags = [:child_count] begin
    # The directive sits on the anchor file, the site the finding reports the directory at.
    files = Fixtures.layout_corpus("pkg"; sizes = [12])
    anchor = findfirst(f -> f.file == "pkg/g1u1.jl", files)
    files[anchor] = Dendro.ParsedFile(
        files[anchor].profile, files[anchor].source, files[anchor].file,
        files[anchor].tree, files[anchor].index,
        [Dendro.Directive(1, Set([:child_count]))],
    )
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_child_count(files, fg; band = (10, 20)))
    @test f.suppressed
end

@testitem ":child_count is off by default and opts in through a config" setup = [Fixtures] tags = [:child_count] begin
    # Both configs set the band, so the toggle is the only thing the two runs differ by and
    # the item stays true whatever the shipped band is retuned to.
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(joinpath(src, "pkg"))
        for f in Fixtures.layout_corpus("pkg"; sizes = [12])
            write(joinpath(src, f.file), f.source)
        end

        off = joinpath(dir, "off.toml")
        write(off, "[bands]\nchild_count = [10, 20]\n")
        quiet = Dendro.analyze(src; config = Fixtures.isolated_config(src, off))
        @test isempty(filter(f -> f.metric == :child_count, quiet))

        on = joinpath(dir, "on.toml")
        write(on, "[bands]\nchild_count = [10, 20]\n[rules]\nchild_count = true\n")
        loud = Dendro.analyze(src; config = Fixtures.isolated_config(src, on))
        f = only(filter(f -> f.metric == :child_count, loud))
        @test f.value == 12
    end
end

@testitem ":child_count fires on the corpus rank alone" setup = [Fixtures] tags = [:child_count] begin
    # Six directories, five of two children and one of six. The band is put out of reach so
    # only the second score can fire, which is the half a uniformly-wide corpus needs: the
    # widest directory stands out against its own corpus even where no absolute edge trips.
    files = Dendro.ParsedFile[
        Fixtures.parsedfile(:julia, "f$(d)$(u)(x) = x\n"; file = "pkg$d/u$u.jl")
            for d in 1:5 for u in 1:2
    ]
    append!(
        files,
        [Fixtures.parsedfile(:julia, "g$u(x) = x\n"; file = "wide/u$u.jl") for u in 1:6]
    )
    fg = Fixtures.filegraph(files)

    f = only(Dendro.cluster_child_count(files, fg; band = (101, 102), min_dirs = 6))
    @test f.value == 6
    @test f.absolute == :ok
    @test f.percentile == 1.0
    @test first(f.locations).file == "wide/u1.jl"
end
