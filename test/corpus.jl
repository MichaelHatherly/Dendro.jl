duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :duplicate, findings))

@testset "analyze clusters duplicates across files" begin
    mktempdir() do dir
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
end

@testset "analyze clusters more than two duplicates" begin
    mktempdir() do dir
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
end

@testset "analyze size gate" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
        write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

        @test isempty(duplicates(analyze(dir)))
        @test length(duplicates(analyze(dir; min_size = 1))) == 1
    end
end

@testset "analyze ignores lone functions" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(p, q)\n    while p > q\n        p -= 1\n    end\n    return p\nend\n")

        @test isempty(duplicates(analyze(dir; min_size = 1)))
    end
end

@testset "analyze does not cluster across languages" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction f2(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "a.py"), "def f(x):\n    y = x + 1\n    return y * 2\ndef f2(x):\n    y = x + 1\n    return y * 2\n")

        # Each language has its own duplicate pair; the (language, hash) key keeps
        # them from merging into one cross-language cluster.
        findings = duplicates(analyze(dir; min_size = 1))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testset "analyze detects duplicates within one file" begin
    mktempdir() do dir
        file = joinpath(dir, "a.jl")
        write(file, "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction g(t)\n    z = t + 9\n    return z * 7\nend\n")

        hit = only(duplicates(analyze(file; min_size = 1)))
        @test hit.value == 2
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testset "analyze respects dendro-ignore: duplicate" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "# dendro-ignore: duplicate\nfunction f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

        findings = analyze(dir; min_size = 1)
        @test any(f -> f.metric == :duplicate && f.suppressed, findings)
        @test isempty(duplicates(active(findings)))
    end
end

@testset "report renders a duplicate cluster" begin
    mktempdir() do dir
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
end

@testset "analyze combines metrics and duplicates" begin
    mktempdir() do dir
        # a and b hold a duplicated pair; c is a separately complex function.
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
        write(joinpath(dir, "c.jl"), "function busy(a, b, c, d, e, f)\n    1\nend\n")

        findings = analyze(dir; min_size = 1)
        @test any(f -> f.metric == :duplicate, findings)
        @test any(f -> f.metric == :parameter_count, findings)
    end
end

@testset "analyze auto-builds a baseline for a folder" begin
    mktempdir() do dir
        # Nine flat functions and one with a branch: the outlier ranks at the top of
        # the corpus distribution, so relative scoring fires without a passed baseline.
        for i in 1:9
            write(joinpath(dir, "flat$i.jl"), "function f$i()\n    $i\nend\n")
        end
        write(joinpath(dir, "odd.jl"), "function g(x)\n    if x > 0\n        1\n    end\nend\n")

        findings = analyze(dir)
        @test any(f -> f.percentile !== nothing, findings)
    end
end

@testset "analyze auto-builds a baseline for a single file" begin
    mktempdir() do dir
        file = joinpath(dir, "g.jl")
        write(file, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

        @test any(f -> f.percentile !== nothing, analyze(file))
    end
end

@testset "analyze gates trivial duplicates by default" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
        write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

        @test isempty(duplicates(analyze(dir)))
    end
end

@testset "analyze skips profileless files" begin
    mktempdir() do dir
        write(joinpath(dir, "readme.md"), "# heading\n")
        @test analyze(dir) == Dendro.Finding[]
    end
end

@testset "analyze detects a duplicated block across functions" begin
    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        # alpha and beta are not whole-function clones: beta has an extra call and a
        # different return. Only the while-loop body is shared, an identical block.
        write(a, "function alpha(x)\n    seen = 0\n    while x > 0\n        seen += x\n        seen *= 2\n        x -= 1\n    end\n    return seen\nend\n")
        write(b, "function beta(p, q)\n    acc = 1\n    helper(q)\n    while p > 0\n        acc += p\n        acc *= 2\n        p -= 1\n    end\n    return acc + q\nend\n")

        hit = only(duplicates(analyze(dir; min_size = 1)))
        @test hit.metric == :duplicate
        @test hit.value == 2
        @test Set(loc.unit for loc in hit.locations) == Set(["alpha", "beta"])
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
    end
end

@testset "maximality reports the function, not its blocks" begin
    mktempdir() do dir
        # Two renamed-clone functions, each with a nested if-block. The function, its
        # body, and the if-body all duplicate; only the maximal one, the function, is
        # reported, so the result is a single finding anchored at line 1.
        src = "function f(x)\n    if x > 0\n        y = x + 1\n        z = y * 2\n        return z\n    end\n    return 0\nend\n"
        write(joinpath(dir, "a.jl"), src)
        write(joinpath(dir, "b.jl"), replace(src, "f(x)" => "g(w)"))

        hits = duplicates(analyze(dir; min_size = 1))
        @test length(hits) == 1
        @test first(hits).value == 2
        @test all(loc.line == 1 for loc in first(hits).locations)
    end
end
