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

    # A bare `function f end` has a name but no call signature: a forward declaration of a
    # zero-method generic function, a contract, not an empty implementation.
    i = Fixtures.idx(:julia, "function f end\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)

    # A zero-argument method with an empty body is a real empty implementation: its
    # signature is the call `f()`, distinguishing it from the forward declaration above.
    i = Fixtures.idx(:julia, "function f() end\n")
    @test Dendro.empty_body(only(Dendro.functions(i)).node, i)

    # A `where`-qualified empty method keeps its call signature, so it stays flagged.
    i = Fixtures.idx(:julia, "function f(x) where T end\n")
    @test Dendro.empty_body(only(Dendro.functions(i)).node, i)
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

@testitem "unused_parameters (julia)" setup = [Fixtures] tags = [:flags] begin
    unused(src) = length(Dendro.unused_parameters(Fixtures.idx(:julia, src)))

    # A parameter no expression in the body references is dead weight.
    @test unused("function f(x, y)\n    return x\nend\n") == 1
    @test unused("function f(x, y)\n    return x + y\nend\n") == 0
    @test unused("f(x, y) = x\n") == 1
    @test unused("f(x, y) = x + y\n") == 0

    # A typed parameter is matched by its name; an unnamed dispatch-only
    # parameter has no name to go unused.
    @test unused("function f(x::Int, y::Int)\n    return x\nend\n") == 1
    @test unused("f(x, ::Int) = x\n") == 0

    # Keyword, default, and slurp parameters count like any other.
    @test unused("function f(x; verbose = false)\n    return x\nend\n") == 1
    @test unused("function f(x, y = 1)\n    return x\nend\n") == 1
    @test unused("function f(x, rest...)\n    return x\nend\n") == 1

    # A leading underscore is the deliberate-unused convention.
    @test unused("function f(x, _unused)\n    return x\nend\n") == 0

    # A use inside a nested closure is a use.
    @test unused("function f(x)\n    return () -> x + 1\nend\n") == 0

    # An arrow closure is not a unit (like a Python lambda), so its parameters are
    # outside the measured surface; a nested short-form def is a unit, and its
    # parameters belong to it.
    @test unused("function f(a)\n    g = (b) -> 1\n    return g(a)\nend\n") == 0
    @test unused("function f(a)\n    helper(b) = 1\n    return helper(a)\nend\n") == 1
    @test unused("function f(a)\n    helper(b) = b + 1\n    return helper(a)\nend\n") == 0

    # Empty and bodyless functions are already the empty_body finding; their
    # parameters are not additionally dead.
    @test unused("function f(x) end\n") == 0
    @test unused("function f end\n") == 0
end

@testitem "unused_parameters across languages" setup = [Fixtures] tags = [:flags] begin
    unused(lang, src) = length(Dendro.unused_parameters(Fixtures.idx(lang, src)))

    @test unused(:python, "def f(a, b):\n    return a\n") == 1
    @test unused(:python, "def f(a, b):\n    return a + b\n") == 0
    @test unused(:python, "def f(a, b=1):\n    return a\n") == 1
    @test unused(:javascript, "function f(a, b) { return a; }") == 1
    @test unused(:javascript, "const f = (a, b) => a;") == 1
    @test unused(:typescript, "function f(a: number, b: number): number { return a; }") == 1
    @test unused(:go, "func f(a int, b int) int { return a }") == 1
    @test unused(:java, "class C { int f(int a, int b) { return a; } }") == 1
    @test unused(:c, "int f(int a, int b) { return a; }") == 1
    @test unused(:cpp, "int f(int a, int b) { return a; }") == 1
    @test unused(:ruby, "def f(a, b)\n  a\nend\n") == 1
    @test unused(:rust, "fn f(a: i32, b: i32) -> i32 { a }") == 1
    @test unused(:php, "<?php function f(\$a, \$b) { return \$a; }") == 1
    @test unused(:php, "<?php function f(\$a, \$b) { return \$a + \$b; }") == 0

    # A bodyless declaration is a contract; its parameters are its signature.
    @test unused(:java, "interface I { void accept(Object o); }\n") == 0
    @test unused(:c, "int f(int a, int b);\n") == 0
    @test unused(:rust, "trait T { fn f(a: i32); }\n") == 0

    # Bash functions have no named parameters, so nothing can go unused.
    @test unused(:bash, "f() {\n  echo hi\n}\n") == 0
end

@testitem "unused_locals (julia)" setup = [Fixtures] tags = [:flags] begin
    unused(src) = length(Dendro.unused_locals(Fixtures.idx(:julia, src)))

    # A local no reference resolves to is a leftover.
    @test unused("function f()\n    x = 1\n    y = 2\n    return x\nend\n") == 1
    @test unused("function f()\n    x = 1\n    return x\nend\n") == 0

    # Reassignment is one variable, flagged once when never read.
    @test unused("function f()\n    x = 1\n    x = 2\n    return 3\nend\n") == 1
    @test unused("function f()\n    x = 1\n    x = 2\n    return x\nend\n") == 0

    # An unused loop binding is flagged; the underscore convention escapes.
    @test unused("function f(n)\n    for i in 1:n\n        g()\n    end\n    return n\nend\n") == 1
    @test unused("function f(n)\n    for _ in 1:n\n        g()\n    end\n    return n\nend\n") == 0
    @test unused("function f()\n    _tmp = g()\n    return 1\nend\n") == 0

    # A top-level binding is visible across files; dead ones belong to
    # `unreferenced`, not here.
    @test unused("x = 1\n") == 0

    # Assignment-shaped non-bindings never flag: a call-site keyword argument and
    # a NamedTuple field.
    @test unused("function f(xs)\n    sort!(xs; by = abs)\n    return xs\nend\n") == 0
    @test unused("function f()\n    return (added = true, cur = 1)\nend\n") == 0

    # Rebinding an enclosing local from a nested scope is the same variable, not a
    # fresh unused definition.
    @test unused("function f(xs)\n    best = 0\n    for x in xs\n        best = x\n    end\n    return best\nend\n") == 0
end

@testitem "unused_locals across languages" setup = [Fixtures] tags = [:flags] begin
    unused(lang, src) = length(Dendro.unused_locals(Fixtures.idx(lang, src)))

    @test unused(:python, "def f():\n    x = 1\n    return 2\n") == 1
    @test unused(:python, "def f():\n    x = 1\n    return x\n") == 0
    @test unused(:javascript, "function f() { const x = 1; return 2; }") == 1
    @test unused(:javascript, "function f() { const x = 1; return x; }") == 0
    @test unused(:typescript, "function f(): number { const x = 1; return 2; }") == 1
    @test unused(:go, "func f() int {\n  a := 1\n  return 2\n}\n") == 1
    @test unused(:java, "class C { int f() { int a = 1; return 2; } }") == 1
    @test unused(:c, "int f() { int a = g(); return 0; }") == 1
    @test unused(:cpp, "int f() { int a = g(); return 0; }") == 1
    @test unused(:ruby, "def f\n  x = 1\n  2\nend\n") == 1
    @test unused(:ruby, "def f\n  x = 1\n  x\nend\n") == 0
    @test unused(:rust, "fn f() -> i32 {\n  let a = 1;\n  2\n}\n") == 1
    @test unused(:rust, "fn f() -> i32 {\n  let a = 1;\n  a\n}\n") == 0

    # A bash variable use is an expansion, `$x`, resolved like any reference.
    @test unused(:bash, "f() {\n  x=1\n  echo \"\$x\"\n}\n") == 0
    @test unused(:bash, "f() {\n  x=1\n  echo hi\n}\n") == 1

    # PHP's scopes query captures no local bindings, so the metric finds nothing.
    @test unused(:php, "<?php function f() { \$x = 1; return 2; }") == 0
end

@testitem "shadowed_variables (julia)" setup = [Fixtures] tags = [:flags] begin
    shadowed(src) = length(Dendro.shadowed_variables(Fixtures.idx(:julia, src)))

    # A loop binding over an existing local is a fresh variable hiding the outer
    # one; so is a `let` binding.
    @test shadowed("function f(n)\n    x = 1\n    for x in 1:n\n        g(x)\n    end\n    return x\nend\n") == 1
    @test shadowed("function f()\n    y = 1\n    let y = 2\n        g(y)\n    end\n    return y\nend\n") == 1

    # A plain assignment inside a loop rebinds the enclosing local, Julia's scope
    # rule, so the accumulator idiom is not a shadow.
    @test shadowed("function f(xs)\n    best = 0\n    for x in xs\n        best = x\n    end\n    return best\nend\n") == 0

    # Distinct names shadow nothing; underscores opt out.
    @test shadowed("function f(n)\n    x = 1\n    for i in 1:n\n        g(i)\n    end\n    return x\nend\n") == 0
    @test shadowed("function f()\n    _x = 1\n    let _x = 2\n        g(_x)\n    end\n    return 1\nend\n") == 0
end

@testitem "shadowed_variables across languages" setup = [Fixtures] tags = [:flags] begin
    shadowed(lang, src) = length(Dendro.shadowed_variables(Fixtures.idx(lang, src)))

    # A nested function's local hiding an enclosing local.
    @test shadowed(:python, "def f():\n    x = 1\n    def g():\n        x = 2\n        return x\n    return g() + x\n") == 1
    @test shadowed(:python, "def f():\n    x = 1\n    def g():\n        y = 2\n        return y\n    return g() + x\n") == 0
    @test shadowed(:javascript, "function f() { let x = 1; function g() { let x = 2; return x; } return g() + x; }") == 1
    @test shadowed(:javascript, "function f() { let x = 1; function g() { let y = 2; return y; } return g() + x; }") == 0
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
