@testset "QueryIndex identifies functions and concepts (julia)" begin
    src = "function f(x)\n    # TODO\n    if x > 0 && x < 9\n        g(x)\n    end\nend\ng(y) = y && y\n"
    i = idx(:julia, src)

    # Both definitions, in source order: the full form and the short form.
    units = Dendro.functions(i)
    @test [Dendro.unit_name(u, i) for u in units] == ["f", "g"]

    # The short form is tagged as such; the full form is not.
    @test units[2].node in i.short_function
    @test !(units[1].node in i.short_function)

    # Concept membership: one `if` (a decision and a nesting construct), one comment,
    # and two `&&` operators across the two functions.
    @test length(i.decision.nodes) == 1
    @test length(i.nesting.nodes) == 1
    @test length(i.comment.nodes) == 1
    @test length(i.short_circuit.nodes) == 2
end

@testset "QueryIndex short-circuit is text-filtered (python)" begin
    # Python's `and`/`or` are anonymous keyword tokens; the query tags exactly those.
    i = idx(:python, "def f(x):\n    return x and y or z\n")
    @test length(i.short_circuit.nodes) == 2
    @test Set(strip(TreeSitter.slice(i.source, n)) for n in i.short_circuit.nodes) == Set(["and", "or"])
end
