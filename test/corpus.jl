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

@testset "analyze_corpus clusters across files" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = Dendro.analyze_corpus([a, b]; min_size = 1)
    hit = only(filter(x -> x.metric == :duplicate, findings))
    @test hit.kind == :flag
    @test hit.value == 2
    @test length(hit.locations) == 2
    files = sort([loc.file for loc in hit.locations])
    @test files == sort([a, b])
    @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    @test all(loc.line == 1 for loc in hit.locations)
end

@testset "analyze_corpus clusters more than two" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    c = joinpath(dir, "c.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
    write(c, "function h(n)\n    m = n + 5\n    return m * 3\nend\n")

    hit = only(Dendro.analyze_corpus([a, b, c]; min_size = 1))
    @test hit.metric == :duplicate
    @test hit.value == 3
    @test length(hit.locations) == 3
    @test sort([loc.file for loc in hit.locations]) == sort([a, b, c])
end

@testset "analyze_corpus size gate" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function getx()\n    x\nend\n")
    write(b, "function getx()\n    x\nend\n")

    @test isempty(Dendro.analyze_corpus([a, b]))
    @test length(Dendro.analyze_corpus([a, b]; min_size = 1)) == 1
end

@testset "analyze_corpus ignores lone functions" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(p, q)\n    while p > q\n        p -= 1\n    end\n    return p\nend\n")

    @test isempty(Dendro.analyze_corpus([a, b]; min_size = 1))
end

@testset "analyze_corpus language argument" begin
    dir = mktempdir()
    a = joinpath(dir, "a.txt")
    b = joinpath(dir, "b.txt")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    @test length(Dendro.analyze_corpus([a, b]; language = "julia", min_size = 1)) == 1
end

@testset "analyze_corpus empty and profileless corpora" begin
    @test Dendro.analyze_corpus(String[]) == Dendro.Finding[]

    dir = mktempdir()
    md = joinpath(dir, "readme.md")
    write(md, "# heading\n")
    @test Dendro.analyze_corpus([md]) == Dendro.Finding[]
end

@testset "analyze_corpus does not cluster across languages" begin
    dir = mktempdir()
    jl = joinpath(dir, "a.jl")
    py = joinpath(dir, "a.py")
    write(jl, "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction f2(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(py, "def f(x):\n    y = x + 1\n    return y * 2\ndef f2(x):\n    y = x + 1\n    return y * 2\n")

    # Each language has its own duplicate pair; the (language, digest) key keeps
    # them from merging into one cross-language cluster.
    findings = Dendro.analyze_corpus([jl, py]; min_size = 1)
    @test length(findings) == 2
    for f in findings
        @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
    end
end

@testset "analyze_corpus respects dendro-ignore: duplicate" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "# dendro-ignore: duplicate\nfunction f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = Dendro.analyze_corpus([a, b]; min_size = 1)
    @test any(f -> f.metric == :duplicate && f.suppressed, findings)
    @test isempty(filter(f -> f.metric == :duplicate, Dendro.active(findings)))
end

@testset "report renders a duplicate cluster" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = Dendro.analyze_corpus([a, b]; min_size = 1)
    io = IOBuffer()
    Dendro.report(io, findings)
    out = String(take!(io))
    @test occursin("duplicate", out)
    @test occursin("also at", out)
    @test occursin("a.jl", out)
    @test occursin("b.jl", out)
    @test occursin("f", out)
    @test occursin("g", out)
end
