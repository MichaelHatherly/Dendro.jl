@testitem "cyclomatic (julia)" setup = [Fixtures] tags = [:metrics] begin
    # A straight-line function has complexity 1.
    simple = "function f(x)\n    x + 1\nend\n"
    u = only(Dendro.functions(Fixtures.idx(:julia, simple)))
    @test Dendro.cyclomatic(u.node, Fixtures.idx(:julia, simple)) == 1

    # if(+1) && (+1) for(+1) while(+1) elseif(+1) ||(+1) ternary(+1) catch(+1)
    # over a base of 1 gives 9. The comprehension guard is not a decision point.
    src = """
    function f(x, y)
        if x > 0 && y > 0
            for i in 1:x
                while i > 0
                    i -= 1
                end
            end
        elseif x < 0 || y < 0
            z = x > 0 ? 1 : 2
        end
        try
            g()
        catch e
            h()
        end
        return [i for i in 1:x if i > 2]
    end
    """
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 9
end

@testitem "cyclomatic on a short-form def (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "f(x) = x > 0 ? x : -x\n"
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 2   # base + ternary
    @test Dendro.function_length(u) == 1
end

@testitem "nested functions do not inflate the enclosing unit (julia)" setup = [Fixtures] tags = [:metrics] begin
    # `outer` owns one `for`; the closure's `if` and `&&` belong to the closure.
    src = """
    function outer(xs)
        for x in xs
            g = function (y)
                if y > 0 && y < 10
                    return y
                end
            end
        end
        return xs
    end
    """
    i = Fixtures.idx(:julia, src)
    units = Dendro.functions(i)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    inner = units[findfirst(u -> u.firstline != 1, units)]

    @test Dendro.cyclomatic(outer.node, i) == 2   # base + for
    @test Dendro.nesting_depth(outer.node, i) == 1      # the for only
    @test Dendro.cyclomatic(inner.node, i) == 3   # base + if + &&
    @test Dendro.nesting_depth(inner.node, i) == 1      # the if only
end

@testitem "function_length (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "function f(x)\n    y = x + 1\n    return y\nend\n"
    u = only(Dendro.functions(Fixtures.idx(:julia, src)))
    @test Dendro.function_length(u) == 4
end

@testitem "nesting_depth (julia)" setup = [Fixtures] tags = [:metrics] begin
    flat = "function f(x)\n    x + 1\nend\n"
    fi = Fixtures.idx(:julia, flat)
    u = only(Dendro.functions(fi))
    @test Dendro.nesting_depth(u.node, fi) == 0

    src = """
    function f(x)
        if x > 0
            for i in 1:x
                while i > 0
                    i -= 1
                end
            end
        end
    end
    """
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.functions(i))
    @test Dendro.nesting_depth(u.node, i) == 3
end

@testitem "parameter_count (julia)" setup = [Fixtures] tags = [:metrics] begin
    i = Fixtures.idx(:julia, "function f(x, y, z)\n    x\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 3

    i = Fixtures.idx(:julia, "function g()\n    0\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 0

    # Type annotations on parameters still count as one parameter each.
    i = Fixtures.idx(:julia, "function h(a::Int, b)\n    a\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 2

    # Keyword arguments are named at the call site, so they do not count: only the
    # two positional parameters before the `;` separator do.
    i = Fixtures.idx(:julia, "function k(a, b::Int; c=1, d=2)\n    a\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 2

    # A keyword-only signature has no positional parameters.
    i = Fixtures.idx(:julia, "function m(; a=1, b=2)\n    a\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 0

    # A comment inside the parentheses is not a parameter. A line comment among the
    # parameters (an author's note, or an inline `dendro-ignore` directive) does not
    # inflate the count.
    i = Fixtures.idx(:julia, "function n(  # a note\n    a, b, c, d,\n)\n    a\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 4

    # A block comment between parameters likewise does not count.
    i = Fixtures.idx(:julia, "function p(a, #= inline =# b, c)\n    a\nend\n")
    @test Dendro.parameter_count(only(Dendro.functions(i)).node, i) == 3
end

@testitem "parameter_count counts only positional params (python)" setup = [Fixtures] tags = [:metrics] begin
    count(src) = (i = Fixtures.idx(:python, src); Dendro.parameter_count(only(Dendro.functions(i)).node, i))

    # `*args`, `**kwargs`, and the keyword-only params after a bare `*` are named at the
    # call site, the same concern Julia's `;` separates, so they do not count.
    @test count("def f(self, a, b, *args, **kwargs):\n    pass\n") == 3
    @test count("def f(a, *, b):\n    pass\n") == 1
    @test count("def f(a, **kwargs):\n    pass\n") == 1

    # An annotated splat (`*args: T`) wraps the splat in a typed parameter; it still
    # opens the keyword region, and a keyword-only param after it does not count.
    @test count("def f(self, a, *args: int, b: str, **kwargs: int):\n    pass\n") == 2

    # A receiver (`self`/`cls`) is positional and counts; a long positional API is a
    # genuine finding.
    @test count("def f(self, a, b, c, d, e):\n    pass\n") == 6

    # A comment inside the parameter list is not a parameter.
    @test count("def f(  # a note\n    a, b, c, d,\n):\n    pass\n") == 4
end

@testitem "boolean_complexity (julia)" setup = [Fixtures] tags = [:metrics] begin
    flat = "function f(a)\n    return a\nend\n"
    fi = Fixtures.idx(:julia, flat)
    @test Dendro.boolean_complexity(only(Dendro.functions(fi)).node, fi) == 0

    # Four operands joined by three operators is one expression of size 3.
    chain = "function f(a, b, c, d)\n    return a && b && c && d\nend\n"
    ci = Fixtures.idx(:julia, chain)
    @test Dendro.boolean_complexity(only(Dendro.functions(ci)).node, ci) == 3

    # Two separate two-operator conditions: the max is 2, not 4.
    split = "function f(a, b, c, d, e, f)\n    if a && b && c\n        x = 1\n    end\n    if d && e && f\n        y = 2\n    end\nend\n"
    si = Fixtures.idx(:julia, split)
    @test Dendro.boolean_complexity(only(Dendro.functions(si)).node, si) == 2
end

@testitem "return_count (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "function f(x)\n    if x > 0\n        return 1\n    end\n    if x < 0\n        return 2\n    end\n    return 3\nend\n"
    i = Fixtures.idx(:julia, src)
    @test Dendro.return_count(only(Dendro.functions(i)).node, i) == 3

    # A nested function's return belongs to the nested unit, not the enclosing one.
    nested = "function outer(x)\n    g = function (y)\n        return y\n    end\n    return x\nend\n"
    ni = Fixtures.idx(:julia, nested)
    units = Dendro.functions(ni)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    @test Dendro.return_count(outer.node, ni) == 1
end

@testitem "cognitive_complexity (julia)" setup = [Fixtures] tags = [:metrics] begin
    # Straight-line code breaks the flow nowhere, so it scores 0.
    simple = "function f(x)\n    x + 1\nend\n"
    si = Fixtures.idx(:julia, simple)
    @test Dendro.cognitive_complexity(only(Dendro.functions(si)).node, si) == 0

    # Nesting is the penalty cyclomatic misses. Three ifs nested three deep cost
    # 1 + 2 + 3 = 6: each decision adds one plus the levels it sits under.
    nested = """
    function f(x)
        if x > 0
            if x > 1
                if x > 2
                    g()
                end
            end
        end
    end
    """
    ni = Fixtures.idx(:julia, nested)
    @test Dendro.cognitive_complexity(only(Dendro.functions(ni)).node, ni) == 6

    # A boolean run adds one however long it is; an operator change starts a new
    # run. `a && b && c` is one run (if + 1 = 2); `a && b || c` is two (if + 2 = 3).
    onerun = "function f(a, b, c)\n    if a && b && c\n        g()\n    end\nend\n"
    oi = Fixtures.idx(:julia, onerun)
    @test Dendro.cognitive_complexity(only(Dendro.functions(oi)).node, oi) == 2

    tworun = "function f(a, b, c)\n    if a && b || c\n        g()\n    end\nend\n"
    ti = Fixtures.idx(:julia, tworun)
    @test Dendro.cognitive_complexity(only(Dendro.functions(ti)).node, ti) == 3

    # A loop, a nested if, and a catch each add one plus their nesting: for (1),
    # if under the loop (2), catch under try (2), for 5.
    mixed = """
    function f(xs)
        for x in xs
            if x > 0
                g(x)
            end
        end
        try
            h()
        catch e
            r()
        end
    end
    """
    mi = Fixtures.idx(:julia, mixed)
    @test Dendro.cognitive_complexity(only(Dendro.functions(mi)).node, mi) == 5

    # A nested function carries its own complexity, not the enclosing unit's.
    closure = """
    function outer(xs)
        g = function (y)
            if y > 0 && y < 10
                return y
            end
        end
        for x in xs
            g(x)
        end
    end
    """
    clo = Fixtures.idx(:julia, closure)
    units = Dendro.functions(clo)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    # outer owns one for (1); the closure's if and && belong to the closure.
    @test Dendro.cognitive_complexity(outer.node, clo) == 1
end

@testitem "cognitive_complexity scores else-if chains flat" setup = [Fixtures] tags = [:metrics] begin
    # SonarSource scores each condition in an if/else-if chain as a flat +1: the
    # continuation is not deeper nested code. `if/elseif/elseif` costs 3, not the
    # 1 + 2 + 2 a naive "decision plus nesting" reading would charge.
    jl = "function f(x)\n if x>0\n a()\n elseif x>1\n b()\n elseif x>2\n c()\n end\nend\n"
    ji = Fixtures.idx(:julia, jl)
    uj = only(Dendro.functions(ji))
    @test Dendro.cognitive_complexity(uj.node, ji) == 3
    # Each arm is still an independent path, so cyclomatic keeps counting them.
    @test Dendro.cyclomatic(uj.node, ji) == 4

    # Python's dedicated `elif_clause` scores the same way.
    py = "def f(x):\n    if x>0:\n        a()\n    elif x>1:\n        b()\n    elif x>2:\n        c()\n"
    pi = Fixtures.idx(:python, py)
    up = only(Dendro.functions(pi))
    @test Dendro.cognitive_complexity(up.node, pi) == 3

    # A decision genuinely nested under the chain still pays the nesting penalty:
    # the `for` sits one level deep inside the elseif body, so it costs +2.
    nested = "function f(x)\n if x>0\n a()\n elseif x>1\n for i in 1:x\n g(i)\n end\n end\nend\n"
    ni = Fixtures.idx(:julia, nested)
    un = only(Dendro.functions(ni))
    @test Dendro.cognitive_complexity(un.node, ni) == 4  # if(1) + elseif(1) + for(2)
end

@testitem "npath (julia)" setup = [Fixtures] tags = [:metrics] begin
    # A straight-line function has one path.
    simple = "function f(x)\n    x + 1\nend\n"
    si = Fixtures.idx(:julia, simple)
    @test Dendro.npath(only(Dendro.functions(si)).node, si) == 1

    # if without else: NP(then) + B(cond) + 1 = 1 + 0 + 1.
    ifonly = "function f(x)\n    if x > 0\n        a()\n    end\nend\n"
    ii = Fixtures.idx(:julia, ifonly)
    @test Dendro.npath(only(Dendro.functions(ii)).node, ii) == 2

    # if/elseif/else is exhaustive: NP(then) + NP(elseif) + NP(else) = 1 + 1 + 1, no
    # fall-through path to add.
    chain = "function f(x)\n    if x > 0\n        a()\n    elseif x < 0\n        b()\n    else\n        c()\n    end\nend\n"
    ci = Fixtures.idx(:julia, chain)
    @test Dendro.npath(only(Dendro.functions(ci)).node, ci) == 3

    # if/elseif without a final else keeps the fall-through path: 1 + 1 + 1 + 1.
    noelse = "function f(x)\n    if x > 0\n        a()\n    elseif x < 0\n        b()\n    elseif x == 0\n        c()\n    end\nend\n"
    ne = Fixtures.idx(:julia, noelse)
    @test Dendro.npath(only(Dendro.functions(ne)).node, ne) == 4

    # A loop adds the skip-the-loop path: NP(body) + 1.
    wh = "function f(x)\n    while x > 0\n        a()\n    end\nend\n"
    wi = Fixtures.idx(:julia, wh)
    @test Dendro.npath(only(Dendro.functions(wi)).node, wi) == 2

    # for-each has no boolean guard: NP(body) + 1.
    fr = "function f(xs)\n    for x in xs\n        a()\n    end\nend\n"
    fi = Fixtures.idx(:julia, fr)
    @test Dendro.npath(only(Dendro.functions(fi)).node, fi) == 2

    # A ternary: NP(then) + NP(else) + B(cond) = 1 + 1 + 0.
    tern = "function f(x)\n    y = x > 0 ? a() : b()\nend\n"
    tei = Fixtures.idx(:julia, tern)
    @test Dendro.npath(only(Dendro.functions(tei)).node, tei) == 2

    # try/catch/finally: NP(try) + NP(catch) + NP(finally) = 1 + 1 + 1.
    tc = "function f()\n    try\n        a()\n    catch e\n        b()\n    finally\n        c()\n    end\nend\n"
    tci = Fixtures.idx(:julia, tc)
    @test Dendro.npath(only(Dendro.functions(tci)).node, tci) == 3

    # Each && / || in a condition adds one path: NP(then) + B + 1 = 1 + 2 + 1.
    bools = "function f(x)\n    if x > 0 && x < 10 || x == 20\n        a()\n    end\nend\n"
    bi = Fixtures.idx(:julia, bools)
    @test Dendro.npath(only(Dendro.functions(bi)).node, bi) == 4

    # Sequential statements multiply: two independent ifs give 2 * 2, not 2 + 2.
    seq = "function f(x)\n    if x > 0\n        a()\n    end\n    if x < 0\n        b()\n    end\nend\n"
    sqi = Fixtures.idx(:julia, seq)
    @test Dendro.npath(only(Dendro.functions(sqi)).node, sqi) == 4

    # Ten flat sequential ifs explode to 2^10 while cyclomatic stays linear at 11,
    # the signal NPath adds.
    tenifs = "function f(x)\n" * repeat("    if x > 0\n        a()\n    end\n", 10) * "end\n"
    ti = Fixtures.idx(:julia, tenifs)
    u = only(Dendro.functions(ti))
    @test Dendro.npath(u.node, ti) == 1024
    @test Dendro.cyclomatic(u.node, ti) == 11

    # A nested function's branches belong to it, not the enclosing unit.
    nested = "function outer(xs)\n    g = function (y)\n        if y > 0\n            return y\n        end\n    end\n    if length(xs) > 0\n        h()\n    end\nend\n"
    ni = Fixtures.idx(:julia, nested)
    units = Dendro.functions(ni)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    @test Dendro.npath(outer.node, ni) == 2   # outer's one if; the closure's is its own

    # The count saturates at NPATH_CAP rather than overflowing Int.
    bigfn = "function f(x)\n" * repeat("    if x > 0\n        a()\n    end\n", 35) * "end\n"
    bgi = Fixtures.idx(:julia, bigfn)
    @test Dendro.npath(only(Dendro.functions(bgi)).node, bgi) == Dendro.NPATH_CAP
end

@testitem "absolute severity bands" tags = [:metrics] begin
    # Classification against a (warn, high) band.
    @test Dendro.severity(10, (11, 21)) == :ok
    @test Dendro.severity(11, (11, 21)) == :warn
    @test Dendro.severity(21, (11, 21)) == :high

    # The built-in bands the classification runs against.
    band(name) = only(r.band for r in Dendro.BUILTIN_RULES if r.name == name)
    @test band(:cyclomatic) == (11, 21)
    @test band(:cognitive_complexity) == (15, 25)
    @test band(:nesting_depth) == (4, 6)
    @test band(:parameter_count) == (5, 8)
    @test band(:function_length) == (50, 100)
end

@testitem "local_count (julia)" setup = [Fixtures] tags = [:metrics] begin
    function count_of(src)
        i = Fixtures.idx(:julia, src)
        u = first(Dendro.functions(i))
        return Dendro.local_count(u, i)
    end

    # Every distinct bound name in the unit counts: plain locals, loop bindings,
    # and locals in nested soft scopes.
    @test count_of("function f(n)\n    a = 1\n    b = 2\n    for i in 1:n\n        c = i\n    end\n    return a + b\nend\n") == 4

    # A rebinding is the same variable.
    @test count_of("function f()\n    x = 1\n    x = 2\n    return x\nend\n") == 1

    # Parameters are not locals; a function with no bindings counts zero.
    @test count_of("function f(x, y)\n    return x + y\nend\n") == 0
end

@testitem "local_count across languages" setup = [Fixtures] tags = [:metrics] begin
    function count_of(lang, src)
        i = Fixtures.idx(lang, src)
        u = first(Dendro.functions(i))
        return Dendro.local_count(u, i)
    end

    @test count_of(:python, "def f():\n    a = 1\n    b = 2\n    return a + b\n") == 2
    @test count_of(:javascript, "function f() { const a = 1, b = 2; return a + b; }") == 2
    @test count_of(:rust, "fn f() -> i32 {\n  let a = 1;\n  let b = 2;\n  a + b\n}\n") == 2

    # PHP's scopes query captures no local bindings, so the count is zero, the
    # honest skip.
    @test count_of(:php, "<?php function f() { \$x = 1; \$y = 2; return \$x + \$y; }") == 0
end

@testitem "shadowed_variable and local_count are optional rules" tags = [:metrics] begin
    names(rules) = [r.name for r in rules]
    @test :shadowed_variable in names(Dendro.OPTIONAL_RULES)
    @test :local_count in names(Dendro.OPTIONAL_RULES)
    @test :shadowed_variable ∉ names(Dendro.BUILTIN_RULES)
    @test :local_count ∉ names(Dendro.BUILTIN_RULES)
    @test only(r.band for r in Dendro.OPTIONAL_RULES if r.name == :local_count) == (10, 15)
end

@testitem "fan_out (julia)" setup = [Fixtures] tags = [:metrics] begin
    function fout(src)
        i = Fixtures.idx(:julia, src)
        u = first(Dendro.functions(i))
        return Dendro.fan_out(u, i)
    end

    # Distinct callables invoked, repeats counted once.
    @test fout("function f(x)\n    a(x)\n    b(x)\n    a(x)\nend\n") == 2

    # A qualified call counts by its final name, so `Base.push!` is `push!`.
    @test fout("function f(x)\n    g(x)\n    Base.push!(x, 1)\nend\n") == 2

    # Recursion is not fan-out, and the signature's own call shape never counts.
    @test fout("function f(x)\n    return x <= 1 ? 1 : f(x - 1)\nend\n") == 0
    @test fout("function f()\n    return 1\nend\n") == 0

    # A nested unit's calls belong to it.
    @test fout("function f(a)\n    helper(b) = g(h(b))\n    return helper(a)\nend\n") == 1
end

@testitem "fan_out across languages" setup = [Fixtures] tags = [:metrics] begin
    function fout(lang, src)
        i = Fixtures.idx(lang, src)
        u = first(Dendro.functions(i))
        return Dendro.fan_out(u, i)
    end

    @test fout(:python, "def f(x):\n    a(x)\n    obj.b(x)\n    a(x)\n") == 2
    @test fout(:javascript, "function f(x) { a(x); obj.b(x); a(x); }") == 2
    @test fout(:go, "func f() {\n  g()\n  x.M()\n}\n") == 2
    @test fout(:java, "class C { void f() { g(); h(); g(); } }") == 2
    @test fout(:c, "int f() { g(); s.h(); return 0; }") == 2
    @test fout(:cpp, "void f() { g(); x.m(); std::h(); }") == 3
    @test fout(:rust, "fn f() { g(); x.m(); a::b::h(); }") == 3
    @test fout(:ruby, "def f\n  g(1)\n  x.m(1)\nend\n") == 2
    @test fout(:php, "<?php function f() { g(); \$x->m(); A\\h(); }") == 3
    @test fout(:bash, "f() {\n  echo hi\n  grep foo bar\n}\n") == 2

    # The method name is the callee; the receiver is not part of the fan.
    @test fout(:python, "def f(x, y):\n    x.push(1)\n    y.push(2)\n") == 1
end

@testitem "fan_out is an optional rule" tags = [:metrics] begin
    names(rules) = [r.name for r in rules]
    @test :fan_out in names(Dendro.OPTIONAL_RULES)
    @test :fan_out ∉ names(Dendro.BUILTIN_RULES)
    @test only(r.band for r in Dendro.OPTIONAL_RULES if r.name == :fan_out) == (12, 20)
end
