@testitem "empty_catches (julia)" setup = [Fixtures] tags = [:flags] begin
    swallowed = "try\n    f()\ncatch\nend\n"
    @test length(Dendro.empty_catches(Fixtures.idx(:julia, swallowed))) == 1

    # An exception variable but no body still swallows the error.
    novar = "try\n    f()\ncatch e\nend\n"
    @test length(Dendro.empty_catches(Fixtures.idx(:julia, novar))) == 1

    handled = "try\n    f()\ncatch e\n    h(e)\nend\n"
    @test isempty(Dendro.empty_catches(Fixtures.idx(:julia, handled)))
end

@testitem "identical_operands (julia)" setup = [Fixtures] tags = [:flags] begin
    flag(src) = length(Dendro.identical_operands(Fixtures.idx(:julia, src)))

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

    # `=>` pairs an identity entry in a canonicalisation table, not a redundant
    # comparison, so a self-mapping is left alone.
    @test flag("f() = Dict(\"Accept\" => \"Accept\")") == 0
    @test flag("f() = (:a => :a)") == 0
end

@testitem "duplicate_branches (julia)" setup = [Fixtures] tags = [:flags] begin
    flag(src) = length(Dendro.duplicate_branches(Fixtures.idx(:julia, src)))

    # Every arm runs the same code, so the condition decides nothing.
    @test flag("if c\n    a()\nelse\n    a()\nend\n") == 1
    @test flag("if c\n    a()\nelseif d\n    a()\nelse\n    a()\nend\n") == 1

    # Distinct arms are the normal case; a single arm has nothing to compare.
    @test flag("if c\n    a()\nelse\n    b()\nend\n") == 0
    @test flag("if c\n    a()\nend\n") == 0
    @test flag("if c\n    a()\nelseif d\n    b()\nelse\n    a()\nend\n") == 0
end

@testitem "unreachable_statements (julia)" setup = [Fixtures] tags = [:flags] begin
    flag(src) = length(Dendro.unreachable_statements(Fixtures.idx(:julia, src)))

    # Code after an unconditional return never runs.
    @test flag("function f()\n    return 1\n    g()\nend\n") == 1
    # One finding per block, anchored on the first dead statement.
    @test flag("function f()\n    return 1\n    g()\n    h()\nend\n") == 1

    @test flag("function f()\n    return 1\nend\n") == 0
    # A conditional return leaves the following code reachable.
    @test flag("function f(x)\n    x > 0 && return 1\n    g()\nend\n") == 0
end

@testitem "redundant-logic rules across languages" setup = [Fixtures] tags = [:flags] begin
    operands(lang, src) = length(Dendro.identical_operands(Fixtures.idx(lang, src)))
    branches(lang, src) = length(Dendro.duplicate_branches(Fixtures.idx(lang, src)))
    dead(lang, src) = length(Dendro.unreachable_statements(Fixtures.idx(lang, src)))

    # identical_operands reads each grammar's binary-expression node.
    @test operands(:python, "x = a == a") == 1
    @test operands(:python, "x = a + a") == 0
    @test operands(:javascript, "y = x === x") == 1
    @test operands(:ruby, "y = a && a") == 1

    # `x / x` builds a NaN (`0.0 / 0.0`) or an identity, not a redundant comparison, so
    # division with equal operands is left alone; an equality check still fires.
    @test operands(:c, "int f() { return x / x; }") == 0
    @test operands(:c, "int f() { return x == x; }") == 1

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

@testitem "stub_markers (julia)" setup = [Fixtures] tags = [:flags] begin
    todo = "function f()\n    # TODO: implement\n    1\nend\n"
    @test length(Dendro.stub_markers(Fixtures.idx(:julia, todo))) == 1

    fixme = "# FIXME later\nx = 1\n"
    @test length(Dendro.stub_markers(Fixtures.idx(:julia, fixme))) == 1

    plain = "function f()\n    # ordinary note\n    1\nend\n"
    @test isempty(Dendro.stub_markers(Fixtures.idx(:julia, plain)))
end

@testitem "empty_body (julia)" setup = [Fixtures] tags = [:flags] begin
    i = Fixtures.idx(:julia, "function g()\nend\n")
    @test Dendro.empty_body(only(Dendro.functions(i)).node, i)

    i = Fixtures.idx(:julia, "function g()\n    1\nend\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)

    # A short-form def's expression body always does work, so it is never empty.
    i = Fixtures.idx(:julia, "f(x) = x + 1\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)
end

@testitem "empty_body across languages" setup = [Fixtures] tags = [:flags] begin
    empties(lang, src) = length(Dendro.empty_bodies(Fixtures.idx(lang, src)))

    # A bodyless declaration is a contract, not an empty implementation: an interface or
    # abstract method, a C++ `= default`/`= delete`, a Rust trait method signature.
    @test empties(:java, "interface I { void accept(Object o); }\n") == 0
    @test empties(:php, "<?php interface I { public function get(\$id); }\n") == 0
    @test empties(:cpp, "struct S { ~S() = default; S(const S&) = delete; };\n") == 0
    @test empties(:rust, "trait T { fn f(); }\n") == 0

    # A concise arrow has an expression body, which always does work.
    @test empties(:javascript, "const f = key => key.toLowerCase();\n") == 0
    @test empties(:typescript, "const f = (m: string) => m.toLowerCase();\n") == 0

    # A constructor whose work is signature-level initialization is not empty: a PHP
    # promoted parameter, a C++ member-initializer list.
    @test empties(:php, "<?php class A { public function __construct(public \$x) {} }\n") == 0
    @test empties(:cpp, "struct S { int v_; S(int v) : v_(v) {} };\n") == 0

    # A present but genuinely empty body is still flagged, the signal worth keeping: a
    # keyword-delimited `def … end`, a brace-bodied no-op method, an empty block arrow,
    # a plain constructor with no initialization.
    @test empties(:ruby, "def f\nend\n") == 1
    @test empties(:cpp, "struct S { void m() {} };\n") == 1
    @test empties(:go, "func (s *T) Record() {}\n") == 1
    @test empties(:javascript, "const f = () => {};\n") == 1
    @test empties(:php, "<?php class A { public function __construct(\$x) {} }\n") == 1
end

@testitem "returns_in_finally (javascript)" setup = [Fixtures] tags = [:flags] begin
    bad = "function f() {\n  try { g(); } finally { return 1; }\n}\n"
    @test length(Dendro.returns_in_finally(Fixtures.idx(:javascript, bad))) == 1

    ok = "function f() {\n  try { g(); } finally { cleanup(); }\n}\n"
    @test isempty(Dendro.returns_in_finally(Fixtures.idx(:javascript, ok)))
end

@testitem "returns_in_finally no-ops without a finally concept (go)" setup = [Fixtures] tags = [:flags] begin
    src = "func f() int {\n  return 0\n}\n"
    @test isempty(Dendro.returns_in_finally(Fixtures.idx(:go, src)))
end

@testitem "trivial_wrappers (julia)" setup = [Fixtures] tags = [:flags] begin
    bare = "function f(x)\n    g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(Fixtures.idx(:julia, bare))) == 1

    returned = "function f(x)\n    return g(x)\nend\n"
    @test length(Dendro.trivial_wrappers(Fixtures.idx(:julia, returned))) == 1

    work = "function f(x)\n    y = g(x)\n    return y + 1\nend\n"
    @test isempty(Dendro.trivial_wrappers(Fixtures.idx(:julia, work)))

    # A short-form def whose expression body is one delegating call is a wrapper;
    # one that does real work is not.
    @test length(Dendro.trivial_wrappers(Fixtures.idx(:julia, "f(x) = g(x)\n"))) == 1
    @test isempty(Dendro.trivial_wrappers(Fixtures.idx(:julia, "f(x) = x + 1\n")))
end
