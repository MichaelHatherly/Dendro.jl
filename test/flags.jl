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

@testset "returns_in_finally (javascript)" begin
    p, prof = fixture(:javascript)

    bad = "function f() {\n  try { g(); } finally { return 1; }\n}\n"
    @test length(Dendro.returns_in_finally(parse(p, bad), prof)) == 1

    ok = "function f() {\n  try { g(); } finally { cleanup(); }\n}\n"
    @test isempty(Dendro.returns_in_finally(parse(p, ok), prof))
end

@testset "returns_in_finally no-ops without a finally concept (go)" begin
    p, prof = fixture(:go)
    src = "func f() int {\n  return 0\n}\n"
    @test isempty(Dendro.returns_in_finally(parse(p, src), prof))
end

@testset "trivial_wrappers (julia)" begin
    p, prof = fixture(:julia)

    bare = "function f(x)\n    g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(parse(p, bare), prof)) == 1

    returned = "function f(x)\n    return g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(parse(p, returned), prof)) == 1

    work = "function f(x)\n    y = g(x)\n    return y + 1\nend\n"
    @test isempty(Dendro.trivial_wrappers(parse(p, work), prof))
end
