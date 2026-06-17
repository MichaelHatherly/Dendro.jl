@testset "dice over sorted multisets" begin
    @test Dendro.dice(UInt64[1, 2, 3], UInt64[1, 2, 3]) == 1.0
    @test Dendro.dice(UInt64[1, 2, 3], UInt64[4, 5, 6]) == 0.0
    # Four shared elements of eight total.
    @test Dendro.dice(UInt64[1, 2, 3, 4], UInt64[3, 4, 5, 6]) == 0.5
    # Multiplicity counts: one shared 1 and one shared 2 of six total.
    @test Dendro.dice(UInt64[1, 1, 2], UInt64[1, 2, 2]) == 2 * 2 / 6
    # Empty inputs never arise above the size gate; guard against a NaN anyway.
    @test Dendro.dice(UInt64[], UInt64[]) == 0.0
end

@testset "subtree_hashes tolerates renames and literals" begin
    p, prof = fixture(:julia)
    a = "function f(x)\n    y = x + 1\n    return y * 2\nend\n"
    b = "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n"
    c = "function h(x)\n    while x > 0\n        x -= 1\n    end\nend\n"
    ha = Dendro.subtree_hashes(only(Dendro.functions(parse(p, a), prof)), prof)
    hb = Dendro.subtree_hashes(only(Dendro.functions(parse(p, b), prof)), prof)
    hc = Dendro.subtree_hashes(only(Dendro.functions(parse(p, c), prof)), prof)
    @test ha == hb
    @test Dendro.dice(ha, hb) == 1.0
    @test Dendro.dice(ha, hc) < 1.0
end

@testset "subtree_hashes excludes nested functions" begin
    p, prof = fixture(:julia)
    plain = "function f(x)\n    y = x + 1\n    return y\nend\n"
    nested = "function f(x)\n    function helper()\n        0\n    end\n    y = x + 1\n    return y\nend\n"
    hp = Dendro.subtree_hashes(first(Dendro.functions(parse(p, plain), prof)), prof)
    hn = Dendro.subtree_hashes(first(Dendro.functions(parse(p, nested), prof)), prof)
    @test hp == hn
end

@testset "subtree_hashes scores near-misses below identity" begin
    p, prof = fixture(:julia)
    base = "function f(x)\n    y = x + 1\n    z = y * 2\n    return z\nend\n"
    near = "function g(t)\n    a = t + 9\n    b = a * 7\n    c = b - 1\n    return c\nend\n"
    hf = Dendro.subtree_hashes(only(Dendro.functions(parse(p, base), prof)), prof)
    hg = Dendro.subtree_hashes(only(Dendro.functions(parse(p, near), prof)), prof)
    d = Dendro.dice(hf, hg)
    @test 0.5 < d < 1.0
end

@testset "node_histogram counts named node types" begin
    p, prof = fixture(:julia)
    u = only(Dendro.functions(parse(p, "function f(x)\n    y = x + 1\n    return y\nend\n"), prof))
    hist = Dendro.node_histogram(u, prof)
    # Both walk the same named-node set, so the totals agree.
    @test sum(values(hist)) == length(Dendro.subtree_hashes(u, prof))
    @test haskey(hist, "identifier")
end

near_duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :near_duplicate, findings))

# A Julia function whose body is `n` chained assignments. Two such with different
# names are renamed clones; with different `n` they are near-misses. Each statement
# adds 7 named nodes, so `n` controls the size band.
chain(name, n) = string("function $name($(name)0)\n",
                        join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
                        "    return $name$n\nend\n")

pychain(name, n) = string("def $name($(name)0):\n",
                          join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
                          "    return $name$n\n")

@testset "analyze clusters near-misses across files" begin
    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, chain("f", 5))
        write(b, chain("g", 6))

        hit = only(near_duplicates(analyze(dir)))
        @test hit.metric == :near_duplicate
        @test hit.kind == :flag
        @test length(hit.locations) == 2
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
        # The value is the weakest pairwise Dice as a percent, above the cutoff.
        @test 85 <= hit.value < 100
    end
end

@testset "exact clones are reported as duplicate, not near_duplicate" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), chain("f", 5))
        write(joinpath(dir, "b.jl"), chain("g", 5))

        findings = analyze(dir)
        @test any(f -> f.metric == :duplicate, findings)
        @test isempty(near_duplicates(findings))
    end
end

@testset "analyze does not cluster dissimilar functions" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), chain("f", 5))
        write(joinpath(dir, "b.jl"),
              "function g(x)\n    while x > 0\n        x -= 1\n        x *= 2\n        x += 3\n    end\n    return x\nend\n")

        @test isempty(near_duplicates(analyze(dir)))
    end
end

@testset "analyze finds near-misses across a size-band boundary" begin
    mktempdir() do dir
        # 58 named nodes (band 5) and 65 (band 6) straddle the power-of-two boundary;
        # the prefilter queries each band against the next so the pair is still seen.
        write(joinpath(dir, "a.jl"), chain("f", 7))
        write(joinpath(dir, "b.jl"), chain("g", 8))

        @test length(near_duplicates(analyze(dir))) == 1
    end
end

@testset "analyze detects near-misses within one file" begin
    mktempdir() do dir
        file = joinpath(dir, "a.jl")
        write(file, string(chain("f", 5), chain("g", 6)))

        hit = only(near_duplicates(analyze(file)))
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testset "analyze does not cluster near-misses across languages" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string(chain("f", 5), chain("g", 6)))
        write(joinpath(dir, "a.py"), string(pychain("f", 5), pychain("g", 6)))

        findings = near_duplicates(analyze(dir))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testset "threshold gates near-misses" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), chain("f", 5))
        write(joinpath(dir, "b.jl"), chain("g", 6))

        @test length(near_duplicates(analyze(dir))) == 1
        @test isempty(near_duplicates(analyze(dir; threshold = 0.95)))
    end
end

@testset "analyze respects dendro-ignore: near_duplicate" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string("# dendro-ignore: near_duplicate\n", chain("f", 5)))
        write(joinpath(dir, "b.jl"), chain("g", 6))

        findings = analyze(dir)
        @test any(f -> f.metric == :near_duplicate && f.suppressed, findings)
        @test isempty(near_duplicates(active(findings)))
    end
end
