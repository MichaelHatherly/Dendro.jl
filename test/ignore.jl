@testset "ignore: leading slash anchors to root" begin
    pats = Dendro.compile_ignores(["/root.jl"])
    @test Dendro.is_ignored(pats, "root.jl", false)
    @test !Dendro.is_ignored(pats, "a/root.jl", false)
end

@testset "ignore: a middle slash anchors to root" begin
    pats = Dendro.compile_ignores(["vendor/x.jl"])
    @test Dendro.is_ignored(pats, "vendor/x.jl", false)
    @test !Dendro.is_ignored(pats, "a/vendor/x.jl", false)
end

@testset "ignore: a bare name matches at any depth" begin
    pats = Dendro.compile_ignores(["build"])
    @test Dendro.is_ignored(pats, "build", true)
    @test Dendro.is_ignored(pats, "a/b/build", true)
end

@testset "ignore: an unanchored glob matches at any depth" begin
    pats = Dendro.compile_ignores(["*.generated.jl"])
    @test Dendro.is_ignored(pats, "x.generated.jl", false)
    @test Dendro.is_ignored(pats, "a/b/x.generated.jl", false)
end

@testset "ignore: a trailing slash matches directories only" begin
    pats = Dendro.compile_ignores(["vendor/"])
    @test Dendro.is_ignored(pats, "vendor", true)
    @test !Dendro.is_ignored(pats, "vendor", false)
end

@testset "ignore: a star stops at a separator" begin
    pats = Dendro.compile_ignores(["gen/*.jl"])
    @test Dendro.is_ignored(pats, "gen/a.jl", false)
    @test !Dendro.is_ignored(pats, "gen/sub/a.jl", false)
end

@testset "ignore: a question mark matches one non-separator char" begin
    pats = Dendro.compile_ignores(["v?.jl"])
    @test Dendro.is_ignored(pats, "va.jl", false)
    @test !Dendro.is_ignored(pats, "vab.jl", false)
end

@testset "ignore: a leading ** spans directories" begin
    pats = Dendro.compile_ignores(["**/gen/a.jl"])
    @test Dendro.is_ignored(pats, "gen/a.jl", false)
    @test Dendro.is_ignored(pats, "x/y/gen/a.jl", false)
end

@testset "ignore: a trailing /** matches everything inside" begin
    pats = Dendro.compile_ignores(["gen/**"])
    @test Dendro.is_ignored(pats, "gen/a.jl", false)
    @test Dendro.is_ignored(pats, "gen/sub/a.jl", false)
    @test !Dendro.is_ignored(pats, "gen", true)
end

@testset "ignore: negation re-includes, last match wins" begin
    pats = Dendro.compile_ignores(["*.jl", "!keep.jl"])
    @test Dendro.is_ignored(pats, "a.jl", false)
    @test !Dendro.is_ignored(pats, "keep.jl", false)
end

@testset "analyze ignores a vendored path" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "vendor"))
        write(joinpath(dir, "vendor", "v.jl"), "function busy(a, b, c, d, e, f)\n    1\nend\n")
        write(joinpath(dir, "s.jl"), "function clean(x)\n    x\nend\n")

        @test any(f -> f.metric == :parameter_count, analyze(dir))

        findings = analyze(dir; ignore = ["vendor/"])
        @test !any(f -> any(loc -> occursin("vendor", loc.file), f.locations), findings)
        @test !any(f -> any(loc -> loc.unit == "busy", f.locations), findings)
    end
end

@testset "ignore removes files from the corpus, not just the findings" begin
    mktempdir() do dir
        # The duplicate exists only between the vendored file and the source file.
        # Ignoring vendor leaves the source function unique, so no clone remains.
        mkpath(joinpath(dir, "vendor"))
        write(joinpath(dir, "vendor", "v.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "s.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

        @test any(f -> f.metric == :duplicate, analyze(dir; min_size = 1))
        @test isempty(duplicates(analyze(dir; min_size = 1, ignore = ["vendor/"])))
    end
end

@testset "analyze honours ignore negation" begin
    mktempdir() do dir
        write(joinpath(dir, "drop.jl"), "function busy(a, b, c, d, e, f)\n    1\nend\n")
        write(joinpath(dir, "keep.jl"), "function alsobusy(a, b, c, d, e, f)\n    1\nend\n")

        findings = analyze(dir; ignore = ["*.jl", "!keep.jl"])
        @test !any(f -> any(loc -> occursin("drop.jl", loc.file), f.locations), findings)
        @test any(f -> any(loc -> occursin("keep.jl", loc.file), f.locations), findings)
    end
end

@testset "ignore is a no-op for a single named file" begin
    mktempdir() do dir
        file = joinpath(dir, "v.jl")
        write(file, "function busy(a, b, c, d, e, f)\n    1\nend\n")
        @test any(f -> f.metric == :parameter_count, analyze(file; ignore = ["*.jl"]))
    end
end
