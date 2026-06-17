@testset "empty_catches (julia)" begin
    p, prof = fixture(:julia)

    swallowed = "try\n    f()\ncatch\nend\n"
    @test length(Dendro.empty_catches(parse(p, swallowed), prof)) == 1

    # An exception variable but no body still swallows the error.
    novar = "try\n    f()\ncatch e\nend\n"
    @test length(Dendro.empty_catches(parse(p, novar), prof)) == 1

    handled = "try\n    f()\ncatch e\n    h(e)\nend\n"
    @test isempty(Dendro.empty_catches(parse(p, handled), prof))
end

@testset "stub_markers (julia)" begin
    p, prof = fixture(:julia)

    todo = "function f()\n    # TODO: implement\n    1\nend\n"
    @test length(Dendro.stub_markers(parse(p, todo), prof, todo)) == 1

    fixme = "# FIXME later\nx = 1\n"
    @test length(Dendro.stub_markers(parse(p, fixme), prof, fixme)) == 1

    plain = "function f()\n    # ordinary note\n    1\nend\n"
    @test isempty(Dendro.stub_markers(parse(p, plain), prof, plain))
end

@testset "empty_body (julia)" begin
    p, prof = fixture(:julia)

    u = only(Dendro.functions(parse(p, "function g()\nend\n"), prof))
    @test Dendro.empty_body(u.node, prof)

    u = only(Dendro.functions(parse(p, "function g()\n    1\nend\n"), prof))
    @test !Dendro.empty_body(u.node, prof)
end
