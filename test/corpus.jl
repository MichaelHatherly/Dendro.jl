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

@testset "find_duplicates clusters across files" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    hit = only(Dendro.find_duplicates([a, b]; min_size = 1))
    @test hit.metric == :duplicate
    @test hit.kind == :flag
    @test hit.value == 2
    @test length(hit.locations) == 2
    @test sort([loc.file for loc in hit.locations]) == sort([a, b])
    @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    @test all(loc.line == 1 for loc in hit.locations)
end

@testset "find_duplicates clusters more than two" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    c = joinpath(dir, "c.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
    write(c, "function h(n)\n    m = n + 5\n    return m * 3\nend\n")

    hit = only(Dendro.find_duplicates([a, b, c]; min_size = 1))
    @test hit.value == 3
    @test length(hit.locations) == 3
    @test sort([loc.file for loc in hit.locations]) == sort([a, b, c])
end

@testset "find_duplicates size gate" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function getx()\n    x\nend\n")
    write(b, "function getx()\n    x\nend\n")

    @test isempty(Dendro.find_duplicates([a, b]))
    @test length(Dendro.find_duplicates([a, b]; min_size = 1)) == 1
end

@testset "find_duplicates ignores lone functions" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(p, q)\n    while p > q\n        p -= 1\n    end\n    return p\nend\n")

    @test isempty(Dendro.find_duplicates([a, b]; min_size = 1))
end

@testset "find_duplicates language argument" begin
    dir = mktempdir()
    a = joinpath(dir, "a.txt")
    b = joinpath(dir, "b.txt")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    @test length(Dendro.find_duplicates([a, b]; language = "julia", min_size = 1)) == 1
end

@testset "find_duplicates empty and profileless corpora" begin
    @test Dendro.find_duplicates(String[]) == Dendro.Finding[]

    dir = mktempdir()
    md = joinpath(dir, "readme.md")
    write(md, "# heading\n")
    @test Dendro.find_duplicates([md]) == Dendro.Finding[]
end

@testset "find_duplicates does not cluster across languages" begin
    dir = mktempdir()
    jl = joinpath(dir, "a.jl")
    py = joinpath(dir, "a.py")
    write(jl, "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction f2(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(py, "def f(x):\n    y = x + 1\n    return y * 2\ndef f2(x):\n    y = x + 1\n    return y * 2\n")

    # Each language has its own duplicate pair; the (language, digest) key keeps
    # them from merging into one cross-language cluster.
    findings = Dendro.find_duplicates([jl, py]; min_size = 1)
    @test length(findings) == 2
    for f in findings
        @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
    end
end

@testset "find_duplicates respects dendro-ignore: duplicate" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "# dendro-ignore: duplicate\nfunction f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = Dendro.find_duplicates([a, b]; min_size = 1)
    @test any(f -> f.metric == :duplicate && f.suppressed, findings)
    @test isempty(filter(f -> f.metric == :duplicate, Dendro.active(findings)))
end

@testset "report renders a duplicate cluster" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

    findings = Dendro.find_duplicates([a, b]; min_size = 1)
    io = IOBuffer()
    Dendro.report(io, findings)
    out = String(take!(io))
    @test occursin("duplicate", out)
    @test occursin("also at", out)
    @test occursin("a.jl", out)
    @test occursin("b.jl", out)
end

@testset "analyze_corpus combines metrics and duplicates" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    # a and b hold a duplicated pair; c is a separately complex function.
    write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
    write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
    c = joinpath(dir, "c.jl")
    write(c, "function busy(a, b, c, d, e, f)\n    1\nend\n")

    findings = Dendro.analyze_corpus([a, b, c]; min_size = 1)
    @test any(f -> f.metric == :duplicate, findings)
    @test any(f -> f.metric == :parameter_count, findings)
end

@testset "analyze_corpus auto-builds a baseline" begin
    dir = mktempdir()
    # Nine flat functions and one with a branch: the outlier ranks at the top of
    # the corpus distribution, so relative scoring fires without a passed baseline.
    paths = String[]
    for i in 1:9
        p = joinpath(dir, "flat$i.jl")
        write(p, "function f$i()\n    $i\nend\n")
        push!(paths, p)
    end
    odd = joinpath(dir, "odd.jl")
    write(odd, "function g(x)\n    if x > 0\n        1\n    end\nend\n")
    push!(paths, odd)

    findings = Dendro.analyze_corpus(paths)
    @test any(f -> f.percentile !== nothing, findings)
end

@testset "analyze_corpus uses a passed baseline" begin
    dir = mktempdir()
    path = joinpath(dir, "g.jl")
    write(path, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

    # A corpus where every function has complexity 1; complexity 2 is an outlier.
    b = Dendro.Baseline(Dict((:julia, :cyclomatic) => fill(1.0, 10)))
    findings = Dendro.analyze_corpus([path]; baseline = b, cut = 0.95)
    hit = only(filter(x -> x.metric == :cyclomatic, findings))
    @test hit.value == 2
    @test hit.percentile == 1.0
end

@testset "analyze_corpus gates trivial duplicates by default" begin
    dir = mktempdir()
    a = joinpath(dir, "a.jl")
    b = joinpath(dir, "b.jl")
    write(a, "function getx()\n    x\nend\n")
    write(b, "function getx()\n    x\nend\n")

    @test isempty(filter(f -> f.metric == :duplicate, Dendro.analyze_corpus([a, b])))
end
