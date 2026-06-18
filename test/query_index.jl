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

# Capture names declared by a compiled query, enumerated through the C API by id.
function capture_names(q::TreeSitter.Query)
    return [
        unsafe_string(TreeSitter.API.ts_query_capture_name_for_id(q.ptr, UInt32(i), Ref{UInt32}()))
            for i in 0:(TreeSitter.capture_count(q) - 1)
    ]
end

@testset "every query uses only known capture names" begin
    # A capture outside CONCEPT_NAMES (or @function) has no field in QueryIndex and
    # would throw in dispatch!. Catch a typo'd capture here, including one that never
    # matches a node, before it reaches a parse.
    valid = Set{String}(string.(Dendro.CONCEPT_NAMES))
    push!(valid, "function")
    @testset "$lang" for lang in sort!(collect(keys(Dendro.PROFILES)))
        @test setdiff(Set(capture_names(Dendro.query_for(lang))), valid) == Set{String}()
    end
end
