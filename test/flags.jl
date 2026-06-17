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

@testset "identical_operands (julia)" begin
    p, prof = fixture(:julia)
    flag(src) = length(Dendro.identical_operands(parse(p, src), prof, src))

    # Equal operands almost always mean a mistake.
    @test flag("f(x) = x == x") == 1
    @test flag("f(a) = a && a") == 1
    @test flag("f(x) = x < x") == 1

    # Different operands are fine, and so is the whole expression nesting: the
    # outer comparison fires once, the inner sums do not.
    @test flag("f(x, y) = x == y") == 0
    @test flag("f(a, b) = (a + b) == (a + b)") == 1

    # Operators where equal operands are ordinary are left alone: doubling and the
    # `x != x` NaN check.
    @test flag("f(x) = x + x") == 0
    @test flag("f(x) = x != x") == 0
end

@testset "duplicate_branches (julia)" begin
    p, prof = fixture(:julia)
    flag(src) = length(Dendro.duplicate_branches(parse(p, src), prof, src))

    # Every arm runs the same code, so the condition decides nothing.
    @test flag("if c\n    a()\nelse\n    a()\nend\n") == 1
    @test flag("if c\n    a()\nelseif d\n    a()\nelse\n    a()\nend\n") == 1

    # Distinct arms are the normal case; a single arm has nothing to compare.
    @test flag("if c\n    a()\nelse\n    b()\nend\n") == 0
    @test flag("if c\n    a()\nend\n") == 0
    @test flag("if c\n    a()\nelseif d\n    b()\nelse\n    a()\nend\n") == 0
end

@testset "unreachable_statements (julia)" begin
    p, prof = fixture(:julia)
    flag(src) = length(Dendro.unreachable_statements(parse(p, src), prof))

    # Code after an unconditional return never runs.
    @test flag("function f()\n    return 1\n    g()\nend\n") == 1
    # One finding per block, anchored on the first dead statement.
    @test flag("function f()\n    return 1\n    g()\n    h()\nend\n") == 1

    @test flag("function f()\n    return 1\nend\n") == 0
    # A conditional return leaves the following code reachable.
    @test flag("function f(x)\n    x > 0 && return 1\n    g()\nend\n") == 0
end

@testset "redundant-logic rules across languages" begin
    operands(lang, src) = length(Dendro.identical_operands(parse(Dendro.parser_for(lang), src), Dendro.PROFILES[lang], src))
    branches(lang, src) = length(Dendro.duplicate_branches(parse(Dendro.parser_for(lang), src), Dendro.PROFILES[lang], src))
    dead(lang, src) = length(Dendro.unreachable_statements(parse(Dendro.parser_for(lang), src), Dendro.PROFILES[lang]))

    # identical_operands reads each grammar's binary-expression node.
    @test operands(:python, "x = a == a") == 1
    @test operands(:python, "x = a + a") == 0
    @test operands(:javascript, "y = x === x") == 1
    @test operands(:ruby, "y = a && a") == 1

    # duplicate_branches reads each grammar's conditional node, with the bodies that
    # belong to one chain.
    @test branches(:python, "if c:\n    a()\nelse:\n    a()\n") == 1
    @test branches(:python, "if c:\n    a()\nelse:\n    b()\n") == 0
    @test branches(:javascript, "if (c) { a(); } else { a(); }") == 1
    @test branches(:javascript, "if (c) { a(); } else { b(); }") == 0

    # unreachable_statements reads each grammar's terminators.
    @test dead(:python, "def f():\n    return 1\n    g()\n") == 1
    @test dead(:javascript, "function f() { return 1; g(); }") == 1
    @test dead(:javascript, "function f() { return 1; }") == 0
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
