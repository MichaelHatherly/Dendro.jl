@testset "clone_similarity is order-aware and asymmetric" begin
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 3, 4]) == 1.0
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[7, 8]) == 0.0
    # Empty inputs never arise above the size gate; guard against a NaN anyway.
    @test Dendro.clone_similarity(UInt64[], UInt64[]) == 0.0
    # A gap (one inserted node) costs proportionally: LCS 4 of the longer length 5.
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 9, 3, 4]) == 0.8
    # Order matters: a reversal shares only one element in sequence, where an
    # order-blind multiset overlap would score these identical.
    @test Dendro.clone_similarity(UInt64[1, 2, 3], UInt64[3, 2, 1]) == 1 / 3
    # A short fragment inside a long one scores low against the longer length, so the
    # verdict rejects it where a multiset overlap would not.
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[1, 2, 9, 9, 9, 9, 9, 9, 9, 9]) == 0.2
end

@testset "subtree_hashes tolerates renames and literals" begin
    a = "function f(x)\n    y = x + 1\n    return y * 2\nend\n"
    b = "function g(total)\n    acc = total + 99\n    return acc * 7\nend\n"
    c = "function h(x)\n    while x > 0\n        x -= 1\n    end\nend\n"
    ia, ib, ic = idx(:julia, a), idx(:julia, b), idx(:julia, c)
    ha = Dendro.subtree_hashes(only(Dendro.functions(ia)), ia)
    hb = Dendro.subtree_hashes(only(Dendro.functions(ib)), ib)
    hc = Dendro.subtree_hashes(only(Dendro.functions(ic)), ic)
    # Renamed identifiers and changed literals leave the structural hashes identical.
    @test ha == hb
    @test ha != hc
end

@testset "subtree_hashes excludes nested functions" begin
    plain = "function f(x)\n    y = x + 1\n    return y\nend\n"
    nested = "function f(x)\n    function helper()\n        0\n    end\n    y = x + 1\n    return y\nend\n"
    ip, inn = idx(:julia, plain), idx(:julia, nested)
    hp = Dendro.subtree_hashes(first(Dendro.functions(ip)), ip)
    hn = Dendro.subtree_hashes(first(Dendro.functions(inn)), inn)
    @test hp == hn
end

@testset "clone_similarity scores near-misses below identity" begin
    base = "function f(x)\n    y = x + 1\n    z = y * 2\n    return z\nend\n"
    near = "function g(t)\n    a = t + 9\n    b = a * 7\n    c = b - 1\n    return c\nend\n"
    ib, inr = idx(:julia, base), idx(:julia, near)
    sf = first(Dendro.clone_features(only(Dendro.functions(ib)), ib))
    sg = first(Dendro.clone_features(only(Dendro.functions(inr)), inr))
    # `near` adds one statement, so its sequence extends `base`'s: similar, not identical.
    @test 0.5 < Dendro.clone_similarity(sf, sg) < 1.0
end

@testset "node_histogram counts named node types" begin
    i = idx(:julia, "function f(x)\n    y = x + 1\n    return y\nend\n")
    u = only(Dendro.functions(i))
    hist = Dendro.node_histogram(u, i)
    # Both walk the same named-node set, so the totals agree.
    @test sum(values(hist)) == length(Dendro.subtree_hashes(u, i))
    @test haskey(hist, "identifier")
end

near_duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :near_duplicate, findings))

# A Julia function whose body is `n` chained assignments. Two such with different
# names are renamed clones; with different `n` they are near-misses. Each statement
# adds 7 named nodes, so `n` controls the size band.
chain(name, n) = string(
    "function $name($(name)0)\n",
    join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
    "    return $name$n\nend\n"
)

pychain(name, n) = string(
    "def $name($(name)0):\n",
    join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
    "    return $name$n\n"
)

@testset "analyze clusters near-misses across files" begin
    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, chain("f", 11))
        write(b, chain("g", 12))

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
        write(
            joinpath(dir, "b.jl"),
            "function g(x)\n    while x > 0\n        x -= 1\n        x *= 2\n        x += 3\n    end\n    return x\nend\n"
        )

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
        write(file, string(chain("f", 11), chain("g", 12)))

        hit = only(near_duplicates(analyze(file)))
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testset "analyze does not cluster near-misses across languages" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string(chain("f", 11), chain("g", 12)))
        write(joinpath(dir, "a.py"), string(pychain("f", 11), pychain("g", 12)))

        findings = near_duplicates(analyze(dir))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testset "threshold gates near-misses" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), chain("f", 11))
        write(joinpath(dir, "b.jl"), chain("g", 12))

        @test length(near_duplicates(analyze(dir))) == 1
        @test isempty(near_duplicates(analyze(dir; threshold = 0.95)))
    end
end

@testset "analyze respects dendro-ignore: near_duplicate" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string("# dendro-ignore: near_duplicate\n", chain("f", 11)))
        write(joinpath(dir, "b.jl"), chain("g", 12))

        findings = analyze(dir)
        @test any(f -> f.metric == :near_duplicate && f.suppressed, findings)
        @test isempty(near_duplicates(active(findings)))
    end
end
