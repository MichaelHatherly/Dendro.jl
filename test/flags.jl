@testset "empty_catches (julia)" begin
    swallowed = "try\n    f()\ncatch\nend\n"
    @test length(Dendro.empty_catches(idx(:julia, swallowed))) == 1

    # An exception variable but no body still swallows the error.
    novar = "try\n    f()\ncatch e\nend\n"
    @test length(Dendro.empty_catches(idx(:julia, novar))) == 1

    handled = "try\n    f()\ncatch e\n    h(e)\nend\n"
    @test isempty(Dendro.empty_catches(idx(:julia, handled)))
end

@testset "identical_operands (julia)" begin
    flag(src) = length(Dendro.identical_operands(idx(:julia, src)))

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
    flag(src) = length(Dendro.duplicate_branches(idx(:julia, src)))

    # Every arm runs the same code, so the condition decides nothing.
    @test flag("if c\n    a()\nelse\n    a()\nend\n") == 1
    @test flag("if c\n    a()\nelseif d\n    a()\nelse\n    a()\nend\n") == 1

    # Distinct arms are the normal case; a single arm has nothing to compare.
    @test flag("if c\n    a()\nelse\n    b()\nend\n") == 0
    @test flag("if c\n    a()\nend\n") == 0
    @test flag("if c\n    a()\nelseif d\n    b()\nelse\n    a()\nend\n") == 0
end

@testset "unreachable_statements (julia)" begin
    flag(src) = length(Dendro.unreachable_statements(idx(:julia, src)))

    # Code after an unconditional return never runs.
    @test flag("function f()\n    return 1\n    g()\nend\n") == 1
    # One finding per block, anchored on the first dead statement.
    @test flag("function f()\n    return 1\n    g()\n    h()\nend\n") == 1

    @test flag("function f()\n    return 1\nend\n") == 0
    # A conditional return leaves the following code reachable.
    @test flag("function f(x)\n    x > 0 && return 1\n    g()\nend\n") == 0
end

@testset "redundant-logic rules across languages" begin
    operands(lang, src) = length(Dendro.identical_operands(idx(lang, src)))
    branches(lang, src) = length(Dendro.duplicate_branches(idx(lang, src)))
    dead(lang, src) = length(Dendro.unreachable_statements(idx(lang, src)))

    # identical_operands reads each grammar's binary-expression node.
    @test operands(:python, "x = a == a") == 1
    @test operands(:python, "x = a + a") == 0
    @test operands(:javascript, "y = x === x") == 1
    @test operands(:ruby, "y = a && a") == 1

    # A chained comparison is one n-ary node, not a binary pair. Comparing its outer
    # two operands would flag `lo <= x <= lo`, which decides nothing trivially.
    @test operands(:python, "x = a == b == a") == 0
    @test operands(:python, "x = lo <= x <= lo") == 0

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
    # PHP `throw` is an expression wrapped in a statement, still a terminator.
    @test dead(:php, "<?php function f() { throw new Exception(); g(); }") == 1
end

@testset "stub_markers (julia)" begin
    todo = "function f()\n    # TODO: implement\n    1\nend\n"
    @test length(Dendro.stub_markers(idx(:julia, todo))) == 1

    fixme = "# FIXME later\nx = 1\n"
    @test length(Dendro.stub_markers(idx(:julia, fixme))) == 1

    plain = "function f()\n    # ordinary note\n    1\nend\n"
    @test isempty(Dendro.stub_markers(idx(:julia, plain)))
end

@testset "empty_body (julia)" begin
    i = idx(:julia, "function g()\nend\n")
    @test Dendro.empty_body(only(Dendro.functions(i)).node, i)

    i = idx(:julia, "function g()\n    1\nend\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)

    # A short-form def's expression body always does work, so it is never empty.
    i = idx(:julia, "f(x) = x + 1\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)
end

@testset "returns_in_finally (javascript)" begin
    bad = "function f() {\n  try { g(); } finally { return 1; }\n}\n"
    @test length(Dendro.returns_in_finally(idx(:javascript, bad))) == 1

    ok = "function f() {\n  try { g(); } finally { cleanup(); }\n}\n"
    @test isempty(Dendro.returns_in_finally(idx(:javascript, ok)))
end

@testset "returns_in_finally no-ops without a finally concept (go)" begin
    src = "func f() int {\n  return 0\n}\n"
    @test isempty(Dendro.returns_in_finally(idx(:go, src)))
end

@testset "trivial_wrappers (julia)" begin
    bare = "function f(x)\n    g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(idx(:julia, bare))) == 1

    returned = "function f(x)\n    return g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(idx(:julia, returned))) == 1

    work = "function f(x)\n    y = g(x)\n    return y + 1\nend\n"
    @test isempty(Dendro.trivial_wrappers(idx(:julia, work)))

    # A short-form def whose expression body is one delegating call is a wrapper;
    # one that does real work is not.
    @test length(Dendro.trivial_wrappers(idx(:julia, "f(x) = g(x)\n"))) == 1
    @test isempty(Dendro.trivial_wrappers(idx(:julia, "f(x) = x + 1\n")))
end
