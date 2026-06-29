@testitem "token_stream (julia)" setup = [Fixtures] tags = [:naturalness] begin
    src = "function f(x)\n    return x + 1\nend\n"
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.functions(i))
    toks = Dendro.token_stream(u, i)

    # Identifiers reduce to their node type; anonymous tokens (keywords, and in
    # Julia the `operator` node) keep their grammar token. The name is gone.
    @test "identifier" in toks
    @test "operator" in toks
    @test "return" in toks
    @test !("x" in toks)
end

@testitem "entropy ranks the surprising function higher" tags = [:naturalness] begin
    common = ["identifier", "=", "identifier", "+", "integer_literal"]
    model = Dendro.build_model([copy(common) for _ in 1:50])

    novel = ["while", "identifier", "<", "identifier", "break"]
    ce(toks) = Dendro.interpolated_cross_entropy(toks, model, model, 1.0)
    @test ce(common) < ce(novel)
end

@testitem "the cache lowers entropy for a file-local idiom" tags = [:naturalness] begin
    idiom_a = ["identifier", "=", "identifier", "+", "integer_literal"]
    idiom_b = ["while", "identifier", "<", "identifier", "break"]
    # The corpus is almost all idiom A, so idiom B is globally surprising.
    global_model = Dendro.build_model([copy(idiom_a) for _ in 1:50])
    # A file that consistently uses idiom B: the cache learns it as local idiom.
    cache = Dendro.build_model([copy(idiom_b) for _ in 1:10])

    global_only = Dendro.interpolated_cross_entropy(idiom_b, global_model, global_model, 1.0)
    with_cache = Dendro.interpolated_cross_entropy(idiom_b, global_model, cache, 0.5)
    # Read against its own file's idiom, the function is less surprising.
    @test with_cache < global_only
end

@testitem "cluster_unnatural guards a thin corpus" setup = [Fixtures] tags = [:naturalness] begin
    src = "function f()\n    1\nend\n"
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    @test isempty(Dendro.cluster_unnatural(files))
end

@testitem "cluster_unnatural ranks the odd function out first" setup = [Fixtures] tags = [:naturalness] begin
    # A corpus of one idiom, plus a function with a structure none of the rest share.
    common = join(["g$i(x) = x + $i" for i in 1:12], "\n")
    odd = "function odd(xs)\n    while true\n        try\n            break\n        catch\n        end\n    end\nend\n"
    src = string(common, "\n", odd, "\n")
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl")]

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9)
    @test !isempty(findings)
    # The surprising function sorts to the top by cross-entropy.
    @test first(findings).metric == :unnatural
    @test first(findings).locations[1].unit == "odd"
end

@testitem "unnatural suppression and scores" setup = [Fixtures] tags = [:naturalness] begin
    common = join(["g$i(x) = x + $i" for i in 1:12], "\n")
    odd = "# dendro-ignore: unnatural\nfunction odd(xs)\n    while true\n        try\n            break\n        catch\n        end\n    end\nend\n"
    src = string(common, "\n", odd, "\n")
    i = Fixtures.idx(:julia, src)
    directives = Dendro.suppressions(i; file = "c.jl")
    files = [Fixtures.parsedfile(:julia, src; file = "c.jl", directives = directives)]

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9)
    odd = only(f for f in findings if f.locations[1].unit == "odd")
    # Two scores travel with the finding, and the directive marks it.
    @test odd.value > 0
    @test odd.percentile !== nothing
    @test odd.suppressed
end
