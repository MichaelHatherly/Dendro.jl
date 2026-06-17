@testset "token_stream (julia)" begin
    p, prof = fixture(:julia)
    src = "function f(x)\n    return x + 1\nend\n"
    u = only(Dendro.functions(parse(p, src), prof))
    toks = Dendro.token_stream(u, prof, src)

    # Identifiers reduce to their node type; anonymous tokens (keywords, and in
    # Julia the `operator` node) keep their grammar token. The name is gone.
    @test "identifier" in toks
    @test "operator" in toks
    @test "return" in toks
    @test !("x" in toks)
end

@testset "cross_entropy ranks the surprising function higher" begin
    common = ["identifier", "=", "identifier", "+", "integer_literal"]
    model = Dendro.build_model([copy(common) for _ in 1:50])

    novel = ["while", "identifier", "<", "identifier", "break"]
    @test Dendro.cross_entropy(common, model) < Dendro.cross_entropy(novel, model)
end

@testset "cluster_unnatural guards a thin corpus" begin
    p, prof = fixture(:julia)
    src = "function f()\n    1\nend\n"
    files = [(language = :julia, profile = prof, source = src, file = "f.jl",
              tree = parse(p, src), directives = Dendro.Directive[])]
    @test isempty(Dendro.cluster_unnatural(files))
end

@testset "cluster_unnatural ranks the odd function out first" begin
    p, prof = fixture(:julia)
    # A corpus of one idiom, plus a function with a structure none of the rest share.
    common = join(["g$i(x) = x + $i" for i in 1:12], "\n")
    odd = "function odd(xs)\n    while true\n        try\n            break\n        catch\n        end\n    end\nend\n"
    src = string(common, "\n", odd, "\n")
    files = [(language = :julia, profile = prof, source = src, file = "c.jl",
              tree = parse(p, src), directives = Dendro.Directive[])]

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9)
    @test !isempty(findings)
    # The surprising function sorts to the top by cross-entropy.
    @test first(findings).metric == :unnatural
    @test first(findings).locations[1].unit == "odd"
end

@testset "unnatural suppression and scores" begin
    p, prof = fixture(:julia)
    common = join(["g$i(x) = x + $i" for i in 1:12], "\n")
    odd = "# dendro-ignore: unnatural\nfunction odd(xs)\n    while true\n        try\n            break\n        catch\n        end\n    end\nend\n"
    src = string(common, "\n", odd, "\n")
    directives = Dendro.suppressions(parse(p, src), prof, src; file = "c.jl")
    files = [(language = :julia, profile = prof, source = src, file = "c.jl",
              tree = parse(p, src), directives = directives)]

    findings = Dendro.cluster_unnatural(files; min_tokens = 0, cut = 0.9)
    odd = only(f for f in findings if f.locations[1].unit == "odd")
    # Two scores travel with the finding, and the directive marks it.
    @test odd.value > 0
    @test odd.percentile !== nothing
    @test odd.suppressed
end
