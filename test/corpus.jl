@testitem "analyze clusters duplicates across files" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

        hit = only(Fixtures.duplicates(analyze(dir; min_size = 1)))
        @test hit.metric == :duplicate
        @test hit.kind == :flag
        @test hit.value == 2
        @test length(hit.locations) == 2
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
        @test all(loc.line == 1 for loc in hit.locations)
    end
end

@testitem "analyze scans multiple roots as one corpus" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do root1
        mktempdir() do root2
            a = joinpath(root1, "a.jl")
            b = joinpath(root2, "b.jl")
            write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
            write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

            hit = only(Fixtures.duplicates(analyze([root1, root2]; min_size = 1)))
            @test hit.value == 2
            @test sort([loc.file for loc in hit.locations]) == sort([a, b])
            @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
        end
    end
end

@testitem "analyze clusters more than two duplicates" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        c = joinpath(dir, "c.jl")
        write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")
        write(c, "function h(n)\n    m = n + 5\n    return m * 3\nend\n")

        hit = only(Fixtures.duplicates(analyze(dir; min_size = 1)))
        @test hit.value == 3
        @test length(hit.locations) == 3
        @test sort([loc.file for loc in hit.locations]) == sort([a, b, c])
    end
end

@testitem "analyze size gate" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
        write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

        @test isempty(Fixtures.duplicates(analyze(dir)))
        @test length(Fixtures.duplicates(analyze(dir; min_size = 1))) == 1
    end
end

@testitem "analyze ignores lone functions" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(p, q)\n    while p > q\n        p -= 1\n    end\n    return p\nend\n")

        @test isempty(Fixtures.duplicates(analyze(dir; min_size = 1)))
    end
end

@testitem "analyze does not cluster across languages" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction f2(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "a.py"), "def f(x):\n    y = x + 1\n    return y * 2\ndef f2(x):\n    y = x + 1\n    return y * 2\n")

        # Each language has its own duplicate pair; the (language, hash) key keeps
        # them from merging into one cross-language cluster.
        findings = Fixtures.duplicates(analyze(dir; min_size = 1))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testitem "analyze detects duplicates within one file" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        file = joinpath(dir, "a.jl")
        write(file, "function f(x)\n    y = x + 1\n    return y * 2\nend\nfunction g(t)\n    z = t + 9\n    return z * 7\nend\n")

        hit = only(Fixtures.duplicates(analyze(file; min_size = 1)))
        @test hit.value == 2
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testitem "analyze respects dendro-ignore: duplicate" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze, active

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "# dendro-ignore: duplicate\nfunction f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(joinpath(dir, "b.jl"), "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

        findings = analyze(dir; min_size = 1)
        @test any(f -> f.metric == :duplicate && f.suppressed, findings)
        @test isempty(Fixtures.duplicates(active(findings)))
    end
end

@testitem "report renders a duplicate cluster" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, "function f(x)\n    y = x + 1\n    return y * 2\nend\n")
        write(b, "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n")

        io = IOBuffer()
        show(io, MIME("text/plain"), Fixtures.duplicates(analyze(dir; min_size = 1)))
        out = String(take!(io))
        @test occursin("duplicate", out)
        @test occursin("also at", out)
        @test occursin("a.jl", out)
        @test occursin("b.jl", out)
    end
end

@testitem "analyze combines metrics and duplicates" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

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

@testitem "analyze auto-builds a baseline for a folder" tags = [:corpus] begin
    using Dendro: analyze

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

@testitem "analyze auto-builds a baseline for a single file" tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        file = joinpath(dir, "g.jl")
        write(file, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

        @test any(f -> f.percentile !== nothing, analyze(file))
    end
end

@testitem "analyze gates trivial duplicates by default" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "function getx()\n    x\nend\n")
        write(joinpath(dir, "b.jl"), "function getx()\n    x\nend\n")

        @test isempty(Fixtures.duplicates(analyze(dir)))
    end
end

@testitem "analyze skips profileless files" tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "readme.md"), "# heading\n")
        @test analyze(dir) == Dendro.Finding[]
    end
end

@testitem "analyze detects a duplicated block across functions" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        # alpha and beta are not whole-function clones: beta has an extra call and a
        # different return. Only the while-loop body is shared, an identical block.
        write(a, "function alpha(x)\n    seen = 0\n    while x > 0\n        seen += x\n        seen *= 2\n        x -= 1\n    end\n    return seen\nend\n")
        write(b, "function beta(p, q)\n    acc = 1\n    helper(q)\n    while p > 0\n        acc += p\n        acc *= 2\n        p -= 1\n    end\n    return acc + q\nend\n")

        hit = only(Fixtures.duplicates(analyze(dir; min_size = 1)))
        @test hit.metric == :duplicate
        @test hit.value == 2
        @test Set(loc.unit for loc in hit.locations) == Set(["alpha", "beta"])
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
    end
end

@testitem "maximality reports the function, not its blocks" setup = [Fixtures] tags = [:corpus] begin
    using Dendro: analyze

    mktempdir() do dir
        # Two renamed-clone functions, each with a nested if-block. The function, its
        # body, and the if-body all duplicate; only the maximal one, the function, is
        # reported, so the result is a single finding anchored at line 1.
        src = "function f(x)\n    if x > 0\n        y = x + 1\n        z = y * 2\n        return z\n    end\n    return 0\nend\n"
        write(joinpath(dir, "a.jl"), src)
        write(joinpath(dir, "b.jl"), replace(src, "f(x)" => "g(w)"))

        hits = Fixtures.duplicates(analyze(dir; min_size = 1))
        @test length(hits) == 1
        @test first(hits).value == 2
        @test all(loc.line == 1 for loc in first(hits).locations)
    end
end
