@testset "structural_digest tolerates renames and literals" begin
    p = Dendro.parser_for(:julia)
    prof = Dendro.PROFILES[:julia]
    a = "function f(x)\n    y = x + 1\n    return y * 2\nend\n"
    b = "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n"
    c = "function h(x)\n    while x > 0\n        x -= 1\n    end\nend\n"
    da, _ = Dendro.structural_digest(only(Dendro.functions(parse(p, a), prof)), prof)
    db, _ = Dendro.structural_digest(only(Dendro.functions(parse(p, b), prof)), prof)
    dc, _ = Dendro.structural_digest(only(Dendro.functions(parse(p, c), prof)), prof)
    @test da == db
    @test da != dc
end

@testset "structural_digest excludes nested functions" begin
    p = Dendro.parser_for(:julia)
    prof = Dendro.PROFILES[:julia]
    plain = "function f(x)\n    y = x + 1\n    return y\nend\n"
    nested = "function f(x)\n    function helper()\n        0\n    end\n    y = x + 1\n    return y\nend\n"
    # The outer unit is the first one traversal yields.
    dp, _ = Dendro.structural_digest(first(Dendro.functions(parse(p, plain), prof)), prof)
    dn, _ = Dendro.structural_digest(first(Dendro.functions(parse(p, nested), prof)), prof)
    @test dp == dn
end

duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :duplicate, findings))

@testset "analyze clusters duplicates across files" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    hit = only(duplicates(analyze(dir; min_size = 1)))
    @test hit.metric == :duplicate
    @test hit.kind == :flag
    @test hit.value == 2
    @test length(hit.locations) == 2
    @test sort([loc.file for loc in hit.locations]) == sort([a, b])
    @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    @test all(loc.line == 1 for loc in hit.locations)
end

@testset "analyze clusters more than two duplicates" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    c = joinpath(dir, "c.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
    write(c, "function h(n)\n    m = n + 5\n    return m * 3\nend\n")

    hit = only(duplicates(analyze(dir; min_size = 1)))
    @test hit.value == 3
    @test length(hit.locations) == 3
    @test sort([loc.file for loc in hit.locations]) == sort([a, b, c])
end

@testset "analyze size gate" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
    write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

    @test isempty(duplicates(analyze(dir)))
    @test length(duplicates(analyze(dir; min_size = 1))) == 1
end

@testset "analyze ignores lone functions" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(joinpath(dir, "b.jl"), "function g(p, q)\n    while p > q\n        p -= 1\n    end\n    return p\nend\n")

    @test isempty(duplicates(analyze(dir; min_size = 1)))
end

@testset "analyze does not cluster across languages" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction f2(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(joinpath(dir, "a.py"), "def f(x):\n    y = x + 1\n    return y * 2\ndef f2(x):\n    y = x + 1\n    return y * 2\n")

    # Each language has its own duplicate pair; the (language, digest) key keeps
    # them from merging into one cross-language cluster.
    findings = duplicates(analyze(dir; min_size = 1))
    @test length(findings) == 2
    for f in findings
        @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
    end
end

@testset "analyze detects duplicates within one file" begin
    dir = mktempdir()
    file = joinpath(dir, "a.jl")
    write(file, "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction g(t)\n    z = t + 9\n    return z * 7\nend\n")

    hit = only(duplicates(analyze(file; min_size = 1)))
    @test hit.value == 2
    @test all(loc.file == file for loc in hit.locations)
    @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
end

@testset "analyze respects dendro-ignore: duplicate" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "# dendro-ignore: duplicate\nfunction f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = analyze(dir; min_size = 1)
    @test any(f -> f.metric == :duplicate && f.suppressed, findings)
    @test isempty(duplicates(active(findings)))
end

@testset "report renders a duplicate cluster" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    io = IOBuffer()
    show(io, MIME("text/plain"), duplicates(analyze(dir; min_size = 1)))
    out = String(take!(io))
    @test occursin("duplicate", out)
    @test occursin("also at", out)
    @test occursin("a.jl", out)
    @test occursin("b.jl", out)
end

@testset "analyze combines metrics and duplicates" begin
    dir = mktempdir()
    # a and b hold a duplicated pair; c is a separately complex function.
    write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
    write(joinpath(dir, "c.jl"), "function busy(a, b, c, d, e, f)\n    1\nend\n")

    findings = analyze(dir; min_size = 1)
    @test any(f -> f.metric == :duplicate, findings)
    @test any(f -> f.metric == :parameter_count, findings)
end

@testset "analyze auto-builds a baseline for a folder" begin
    dir = mktempdir()
    # Nine flat functions and one with a branch: the outlier ranks at the top of
    # the corpus distribution, so relative scoring fires without a passed baseline.
    for i in 1:9
        write(joinpath(dir, "flat$i.jl"), "function f$i()\n    $i\nend\n")
    end
    write(joinpath(dir, "odd.jl"), "function g(x)\n    if x > 0\n        1\n    end\nend\n")

    findings = analyze(dir)
    @test any(f -> f.percentile !== nothing, findings)
end

@testset "analyze auto-builds a baseline for a single file" begin
    dir = mktempdir()
    file = joinpath(dir, "g.jl")
    write(file, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

    @test any(f -> f.percentile !== nothing, analyze(file))
end

@testset "analyze gates trivial duplicates by default" begin
    dir = mktempdir()
    write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
    write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

    @test isempty(duplicates(analyze(dir)))
end

@testset "analyze skips profileless files" begin
    dir = mktempdir()
    write(joinpath(dir, "readme.md"), "# heading\n")
    @test analyze(dir) == Dendro.Finding[]
end
