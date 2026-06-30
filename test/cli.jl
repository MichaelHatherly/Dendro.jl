@testitem "cli help and version exit 0" tags = [:cli] begin
    import Dendro

    redirect_stdout(devnull) do
        @test Dendro.main(["--help"]) == 0
        @test Dendro.main(["-h"]) == 0
        @test Dendro.main(["--version"]) == 0
    end
end

@testitem "cli usage errors exit 1" tags = [:cli] begin
    import Dendro

    redirect_stdout(devnull) do
        redirect_stderr(devnull) do
            @test Dendro.main(String[]) == 1
            @test Dendro.main(["--bogus", "x"]) == 1
            @test Dendro.main(["--format=toml", "x"]) == 1
        end
    end
end

@testitem "cli check gates on findings" setup = [Fixtures] tags = [:cli] begin
    import Dendro

    # A module whose exported `run` reaches `f`, so nothing reads as dead code and the
    # only findings are the percentile outliers a high cut suppresses.
    mktempdir() do dir
        write(joinpath(dir, "m.jl"), Fixtures.modsrc(["f(1)"], Fixtures.guards("f", 6)))
        redirect_stdout(devnull) do
            @test Dendro.main(["--check", dir]) == 1               # percentile flags fire
            @test Dendro.main(["--check", "--cut=1.01", dir]) == 0 # nothing left to flag
            @test Dendro.main([dir]) == 0                          # no --check, always 0
        end
    end
end

@testitem "cli github format emits annotations" setup = [Fixtures] tags = [:cli] begin
    import Dendro

    mktempdir() do dir
        write(joinpath(dir, "f.jl"), Fixtures.guards("f", 6))
        out = mktemp() do path, io
            rc = redirect_stdout(io) do
                Dendro.main(["--format=github", dir])
            end
            @test rc == 0
            flush(io)
            read(path, String)
        end
        @test occursin("::warning", out) || occursin("::error", out)
    end
end
