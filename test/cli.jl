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

@testitem "cli check gates on the high floor" setup = [Fixtures] tags = [:cli] begin
    import Dendro

    # A reachable function nesting six `if` blocks trips nesting_depth's :high band, so
    # the gate fails. The percentile-ranked report is never empty, so the gate reads the
    # satisfiable floor, not every finding.
    mktempdir() do dir
        write(joinpath(dir, "m.jl"), Fixtures.modsrc(["d(1)"], Fixtures.deepfn("d")))
        redirect_stdout(devnull) do
            @test Dendro.main(["--check", dir]) == 1   # a :high finding fails the gate
            @test Dendro.main([dir]) == 0              # no --check, the report exits 0
        end
    end

    # A reachable function under every band leaves the high floor empty, so the gate
    # passes even though the percentile report still flags it.
    mktempdir() do dir
        write(joinpath(dir, "m.jl"), Fixtures.modsrc(["f(1)"], Fixtures.guards("f", 6)))
        redirect_stdout(devnull) do
            @test Dendro.main(["--check", dir]) == 0
        end
    end
end

@testitem "cli reports input errors cleanly" setup = [Fixtures] tags = [:cli] begin
    import Dendro

    redirect_stdout(devnull) do
        redirect_stderr(devnull) do
            @test Dendro.main(["--cut=abc", "."]) == 1            # cut is not a number
            @test Dendro.main(["--config=/no/such.toml", "."]) == 1  # explicit config missing
            @test Dendro.main(["/no/such/path"]) == 1            # path does not exist
            mktempdir() do dir
                bad = joinpath(dir, ".dendro.toml")
                write(bad, "cut = =\n")                          # malformed TOML
                @test Dendro.main(["--config=$bad", dir]) == 1
            end
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
