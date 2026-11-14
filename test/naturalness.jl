@testitem "token_stream (julia)" setup = [Fixtures] tags = [:naturalness] begin
    src = "function f(x)\n    return x + 1\nend\n"
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.units(i))
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

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, min_unit_tokens = 0, cut = 0.9)
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

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, min_unit_tokens = 0, cut = 0.9)
    odd = only(f for f in findings if f.locations[1].unit == "odd")
    # Two scores travel with the finding, and the directive marks it.
    @test odd.value > 0
    @test odd.percentile !== nothing
    @test odd.suppressed
end

@testitem "cluster_unnatural leaves a function under the token floor unscored" setup = [Fixtures] tags = [:naturalness] begin
    # A mean over a handful of tokens is sampling noise, so a one-line function reads as
    # surprising on whichever few trigrams it happens to hold. The odd function is the
    # one a ranking test sorts first, short enough to sit under the floor.
    common = join(["g$i(x) = x + $i" for i in 1:12], "\n")
    loop = "    while xs\n        try\n            break\n        catch\n        end\n    end\n"
    short = string("function odd(xs)\n", loop, "end\n")
    files = [Fixtures.parsedfile(:julia, string(common, "\n", short); file = "c.jl")]
    @test isempty(Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9))

    # The same structure at length is scored, and ranks alone: the short units around it
    # are neither reported nor sampled into its percentile.
    long = string("function odd(xs)\n", loop^4, "end\n")
    files = [Fixtures.parsedfile(:julia, string(common, "\n", long); file = "c.jl")]
    hit = only(Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9))
    @test hit.locations[1].unit == "odd"
    @test hit.percentile == 1.0

    i = files[1].index
    lengths = Dict(Dendro.unit_name(u, i) => length(Dendro.token_stream(u, i)) for u in Dendro.units(i))
    @test lengths["odd"] >= Dendro.MIN_UNIT_TOKENS
    @test all(n < Dendro.MIN_UNIT_TOKENS for (name, n) in lengths if name != "odd")
end
