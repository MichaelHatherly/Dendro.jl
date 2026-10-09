@testitem "cyclomatic (julia)" setup = [Fixtures] tags = [:metrics] begin
    # A straight-line function has complexity 1.
    simple = "function f(x)\n    x + 1\nend\n"
    u = only(Dendro.units(Fixtures.idx(:julia, simple)))
    @test Dendro.cyclomatic(u, Fixtures.idx(:julia, simple)) == 1

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
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 9
end

@testitem "cyclomatic on a short-form def (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "f(x) = x > 0 ? x : -x\n"
    i = Fixtures.idx(:julia, src)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 2   # base + ternary
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
    units = Dendro.units(i)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    inner = units[findfirst(u -> u.firstline != 1, units)]

    @test Dendro.cyclomatic(outer, i) == 2   # base + for
    @test Dendro.nesting_depth(outer, i) == 1      # the for only
    @test Dendro.cyclomatic(inner, i) == 3   # base + if + &&
    @test Dendro.nesting_depth(inner, i) == 1      # the if only
end

@testitem "function_length (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "function f(x)\n    y = x + 1\n    return y\nend\n"
    u = only(Dendro.units(Fixtures.idx(:julia, src)))
    @test Dendro.function_length(u) == 4
end

@testitem "nesting_depth (julia)" setup = [Fixtures] tags = [:metrics] begin
    flat = "function f(x)\n    x + 1\nend\n"
    fi = Fixtures.idx(:julia, flat)
    u = only(Dendro.units(fi))
    @test Dendro.nesting_depth(u, fi) == 0

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
    u = only(Dendro.units(i))
    @test Dendro.nesting_depth(u, i) == 3
end

@testitem "parameter_count (julia)" setup = [Fixtures] tags = [:metrics] begin
    i = Fixtures.idx(:julia, "function f(x, y, z)\n    x\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 3

    i = Fixtures.idx(:julia, "function g()\n    0\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 0

    # Type annotations on parameters still count as one parameter each.
    i = Fixtures.idx(:julia, "function h(a::Int, b)\n    a\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 2

    # Keyword arguments are named at the call site, so they do not count: only the
    # two positional parameters before the `;` separator do.
    i = Fixtures.idx(:julia, "function k(a, b::Int; c=1, d=2)\n    a\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 2

    # A keyword-only signature has no positional parameters.
    i = Fixtures.idx(:julia, "function m(; a=1, b=2)\n    a\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 0

    # A comment inside the parentheses is not a parameter. A line comment among the
    # parameters (an author's note, or an inline `dendro-ignore` directive) does not
    # inflate the count.
    i = Fixtures.idx(:julia, "function n(  # a note\n    a, b, c, d,\n)\n    a\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 4

    # A block comment between parameters likewise does not count.
    i = Fixtures.idx(:julia, "function p(a, #= inline =# b, c)\n    a\nend\n")
    @test Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i) == 3
end

@testitem "parameter_count counts only positional params (python)" setup = [Fixtures] tags = [:metrics] begin
    count(src) = (i = Fixtures.idx(:python, src); Dendro.parameter_count(Dendro.unit_node(only(Dendro.units(i))), i))

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
    @test Dendro.boolean_complexity(only(Dendro.units(fi)), fi) == 0

    # Four operands joined by three operators is one expression of size 3.
    chain = "function f(a, b, c, d)\n    return a && b && c && d\nend\n"
    ci = Fixtures.idx(:julia, chain)
    @test Dendro.boolean_complexity(only(Dendro.units(ci)), ci) == 3

    # Two separate two-operator conditions: the max is 2, not 4.
    split = "function f(a, b, c, d, e, f)\n    if a && b && c\n        x = 1\n    end\n    if d && e && f\n        y = 2\n    end\nend\n"
    si = Fixtures.idx(:julia, split)
    @test Dendro.boolean_complexity(only(Dendro.units(si)), si) == 2
end

@testitem "return_count (julia)" setup = [Fixtures] tags = [:metrics] begin
    src = "function f(x)\n    if x > 0\n        return 1\n    end\n    if x < 0\n        return 2\n    end\n    return 3\nend\n"
    i = Fixtures.idx(:julia, src)
    @test Dendro.return_count(Dendro.unit_node(only(Dendro.units(i))), i) == 3

    # A nested function's return belongs to the nested unit, not the enclosing one.
    nested = "function outer(x)\n    g = function (y)\n        return y\n    end\n    return x\nend\n"
    ni = Fixtures.idx(:julia, nested)
    units = Dendro.units(ni)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    @test Dendro.return_count(outer, ni) == 1
end

@testitem "cognitive_complexity (julia)" setup = [Fixtures] tags = [:metrics] begin
    # Straight-line code breaks the flow nowhere, so it scores 0.
    simple = "function f(x)\n    x + 1\nend\n"
    si = Fixtures.idx(:julia, simple)
    @test Dendro.cognitive_complexity(only(Dendro.units(si)), si) == 0

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
    @test Dendro.cognitive_complexity(only(Dendro.units(ni)), ni) == 6

    # A boolean run adds one however long it is; an operator change starts a new
    # run. `a && b && c` is one run (if + 1 = 2); `a && b || c` is two (if + 2 = 3).
    onerun = "function f(a, b, c)\n    if a && b && c\n        g()\n    end\nend\n"
    oi = Fixtures.idx(:julia, onerun)
    @test Dendro.cognitive_complexity(only(Dendro.units(oi)), oi) == 2

    tworun = "function f(a, b, c)\n    if a && b || c\n        g()\n    end\nend\n"
    ti = Fixtures.idx(:julia, tworun)
    @test Dendro.cognitive_complexity(only(Dendro.units(ti)), ti) == 3

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
    @test Dendro.cognitive_complexity(only(Dendro.units(mi)), mi) == 5

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
    units = Dendro.units(clo)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    # outer owns one for (1); the closure's if and && belong to the closure.
    @test Dendro.cognitive_complexity(outer, clo) == 1
end

@testitem "cognitive_complexity scores else-if chains flat" setup = [Fixtures] tags = [:metrics] begin
    # SonarSource scores each condition in an if/else-if chain as a flat +1: the
    # continuation is not deeper nested code. `if/elseif/elseif` costs 3, not the
    # 1 + 2 + 2 a naive "decision plus nesting" reading would charge.
    jl = "function f(x)\n if x>0\n a()\n elseif x>1\n b()\n elseif x>2\n c()\n end\nend\n"
    ji = Fixtures.idx(:julia, jl)
    uj = only(Dendro.units(ji))
    @test Dendro.cognitive_complexity(uj, ji) == 3
    # Each arm is still an independent path, so cyclomatic keeps counting them.
    @test Dendro.cyclomatic(uj, ji) == 4

    # Python's dedicated `elif_clause` scores the same way.
    py = "def f(x):\n    if x>0:\n        a()\n    elif x>1:\n        b()\n    elif x>2:\n        c()\n"
    pi = Fixtures.idx(:python, py)
    up = only(Dendro.units(pi))
    @test Dendro.cognitive_complexity(up, pi) == 3

    # A decision genuinely nested under the chain still pays the nesting penalty:
    # the `for` sits one level deep inside the elseif body, so it costs +2.
    nested = "function f(x)\n if x>0\n a()\n elseif x>1\n for i in 1:x\n g(i)\n end\n end\nend\n"
    ni = Fixtures.idx(:julia, nested)
    un = only(Dendro.units(ni))
    @test Dendro.cognitive_complexity(un, ni) == 4  # if(1) + elseif(1) + for(2)
end

@testitem "npath (julia)" setup = [Fixtures] tags = [:metrics] begin
    # A straight-line function has one path.
    simple = "function f(x)\n    x + 1\nend\n"
    si = Fixtures.idx(:julia, simple)
    @test Dendro.npath(only(Dendro.units(si)), si) == 1

    # if without else: NP(then) + B(cond) + 1 = 1 + 0 + 1.
    ifonly = "function f(x)\n    if x > 0\n        a()\n    end\nend\n"
    ii = Fixtures.idx(:julia, ifonly)
    @test Dendro.npath(only(Dendro.units(ii)), ii) == 2

    # if/elseif/else is exhaustive: NP(then) + NP(elseif) + NP(else) = 1 + 1 + 1, no
    # fall-through path to add.
    chain = "function f(x)\n    if x > 0\n        a()\n    elseif x < 0\n        b()\n    else\n        c()\n    end\nend\n"
    ci = Fixtures.idx(:julia, chain)
    @test Dendro.npath(only(Dendro.units(ci)), ci) == 3

    # if/elseif without a final else keeps the fall-through path: 1 + 1 + 1 + 1.
    noelse = "function f(x)\n    if x > 0\n        a()\n    elseif x < 0\n        b()\n    elseif x == 0\n        c()\n    end\nend\n"
    ne = Fixtures.idx(:julia, noelse)
    @test Dendro.npath(only(Dendro.units(ne)), ne) == 4

    # A loop adds the skip-the-loop path: NP(body) + 1.
    wh = "function f(x)\n    while x > 0\n        a()\n    end\nend\n"
    wi = Fixtures.idx(:julia, wh)
    @test Dendro.npath(only(Dendro.units(wi)), wi) == 2

    # for-each has no boolean guard: NP(body) + 1.
    fr = "function f(xs)\n    for x in xs\n        a()\n    end\nend\n"
    fi = Fixtures.idx(:julia, fr)
    @test Dendro.npath(only(Dendro.units(fi)), fi) == 2

    # A ternary: NP(then) + NP(else) + B(cond) = 1 + 1 + 0.
    tern = "function f(x)\n    y = x > 0 ? a() : b()\nend\n"
    tei = Fixtures.idx(:julia, tern)
    @test Dendro.npath(only(Dendro.units(tei)), tei) == 2

    # try/catch/finally: NP(try) + NP(catch) + NP(finally) = 1 + 1 + 1.
    tc = "function f()\n    try\n        a()\n    catch e\n        b()\n    finally\n        c()\n    end\nend\n"
    tci = Fixtures.idx(:julia, tc)
    @test Dendro.npath(only(Dendro.units(tci)), tci) == 3

    # Each && / || in a condition adds one path: NP(then) + B + 1 = 1 + 2 + 1.
    bools = "function f(x)\n    if x > 0 && x < 10 || x == 20\n        a()\n    end\nend\n"
    bi = Fixtures.idx(:julia, bools)
    @test Dendro.npath(only(Dendro.units(bi)), bi) == 4

    # Sequential statements multiply: two independent ifs give 2 * 2, not 2 + 2.
    seq = "function f(x)\n    if x > 0\n        a()\n    end\n    if x < 0\n        b()\n    end\nend\n"
    sqi = Fixtures.idx(:julia, seq)
    @test Dendro.npath(only(Dendro.units(sqi)), sqi) == 4

    # Ten flat sequential ifs explode to 2^10 while cyclomatic stays linear at 11,
    # the signal NPath adds.
    tenifs = "function f(x)\n" * repeat("    if x > 0\n        a()\n    end\n", 10) * "end\n"
    ti = Fixtures.idx(:julia, tenifs)
    u = only(Dendro.units(ti))
    @test Dendro.npath(u, ti) == 1024
    @test Dendro.cyclomatic(u, ti) == 11

    # A nested function's branches belong to it, not the enclosing unit.
    nested = "function outer(xs)\n    g = function (y)\n        if y > 0\n            return y\n        end\n    end\n    if length(xs) > 0\n        h()\n    end\nend\n"
    ni = Fixtures.idx(:julia, nested)
    units = Dendro.units(ni)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    @test Dendro.npath(outer, ni) == 2   # outer's one if; the closure's is its own

    # The count saturates at NPATH_CAP rather than overflowing Int.
    bigfn = "function f(x)\n" * repeat("    if x > 0\n        a()\n    end\n", 35) * "end\n"
    bgi = Fixtures.idx(:julia, bigfn)
    @test Dendro.npath(only(Dendro.units(bgi)), bgi) == Dendro.NPATH_CAP
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
        u = first(Dendro.units(i))
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
        u = first(Dendro.units(i))
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
        u = first(Dendro.units(i))
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
        u = first(Dendro.units(i))
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

@testitem "comment_density (julia)" setup = [Fixtures] tags = [:metrics] begin
    function density(src)
        i = Fixtures.idx(:julia, src)
        return Dendro.comment_density(first(Dendro.units(i)), i)
    end

    # Eleven lines, four of them comment. 4/11 rounds to 36.
    narrated = """
    function f(xs)
        # narrate the setup
        total = 0
        # narrate the loop
        for x in xs
            # narrate the add
            total += x
        end
        # narrate the return
        return total
    end
    """
    @test density(narrated) == 36

    # A block comment counts every line it spans: three of eleven rounds to 27.
    blocked = """
    function g(x)
        #= a block comment
           spanning three
           source lines =#
        y = x + 1
        z = y * 2
        w = z - 3
        v = w + 4
        u = v * 5
        return u
    end
    """
    @test density(blocked) == 27

    # A trailing comment counts the one line it sits on: two of ten is 20.
    trailing = """
    function h(x)
        y = x + 1   # why one
        z = y * 2   # why two
        a = z + 3
        b = a + 4
        c = b + 5
        d = c + 6
        e = d + 7
        return e
    end
    """
    @test density(trailing) == 20

    # Ten lines of code and nothing said about them.
    bare = """
    function k(x)
        a = x + 1
        b = a + 2
        c = b + 3
        d = c + 4
        e = d + 5
        g = e + 6
        h = g + 7
        return h
    end
    """
    @test density(bare) == 0
end

@testitem "comment_density (python)" setup = [Fixtures] tags = [:metrics] begin
    src = """
    def f(xs):
        # one
        total = 0
        # two
        for x in xs:
            # three
            total += x
        # four
        total = total * 2
        return total
    """
    i = Fixtures.idx(:python, src)
    @test Dendro.comment_density(first(Dendro.units(i)), i) == 40
end

@testitem "comment_density stops at a nested callable (julia)" setup = [Fixtures] tags = [:metrics] begin
    # The closure's narration is the closure's. `outer` keeps its own one comment over
    # its fourteen lines; the closure scores its two over the ten it spans.
    src = """
    function outer(xs)
        # outer narration
        inner = function (y)
            # inner narration
            # more inner narration
            a = y + 1
            b = a + 2
            c = b + 3
            d = c + 4
            e = d + 5
            return e
        end
        return inner(first(xs))
    end
    """
    i = Fixtures.idx(:julia, src)
    units = Dendro.units(i)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    inner = units[findfirst(u -> u.firstline == 3, units)]

    @test Dendro.comment_density(outer, i) == 7
    @test Dendro.comment_density(inner, i) == 20
end

@testitem "comment_density reads nothing below the length floor" setup = [Fixtures] tags = [:metrics] begin
    function density(src)
        i = Fixtures.idx(:julia, src)
        return Dendro.comment_density(first(Dendro.units(i)), i)
    end

    # One line with one comment is 100% and says nothing, which is what the floor is for.
    @test density("f(x) = x  # why\n") == 0
    @test density("function f(x)\n    # why\n    return x\nend\n") == 0

    # Nine lines stay silent; the tenth is where the ratio starts being read.
    short = """
    function f(x)
        # why
        a = x + 1
        b = a + 2
        c = b + 3
        d = c + 4
        e = d + 5
        return e
    end
    """
    @test density(short) == 0
    @test Dendro.MIN_COMMENT_DENSITY_LINES == 10

    long = """
    function f(x)
        # why
        a = x + 1
        b = a + 2
        c = b + 3
        d = c + 4
        e = d + 5
        g = e + 6
        return g
    end
    """
    @test density(long) == 10
end

@testitem "a docstring never reaches comment_density" setup = [Fixtures] tags = [:metrics] begin
    # A Python or Julia docstring is a string node, and every other language attaches its
    # doc comment as a sibling of the definition rather than a descendant, so no callable
    # here scores for the documentation written above it.
    documented = Dict(
        :julia => """
            \"\"\"
                f(x)

            Add seven, one step at a time.
            \"\"\"
            function f(x)
                a = x + 1
                b = a + 1
                c = b + 1
                d = c + 1
                e = d + 1
                g = e + 1
                h = g + 1
                return h
            end
            """,
        :python => """
            def f(x):
                \"\"\"Add seven, one step at a time.\"\"\"
                a = x + 1
                b = a + 1
                c = b + 1
                d = c + 1
                e = d + 1
                g = e + 1
                h = g + 1
                return h
            """,
        :javascript => """
            /**
             * Add seven, one step at a time.
             */
            function f(x) {
              let a = x + 1;
              let b = a + 1;
              let c = b + 1;
              let d = c + 1;
              let e = d + 1;
              let g = e + 1;
              let h = g + 1;
              return h;
            }
            """,
        :typescript => """
            /**
             * Add seven, one step at a time.
             */
            function f(x: number): number {
              let a = x + 1;
              let b = a + 1;
              let c = b + 1;
              let d = c + 1;
              let e = d + 1;
              let g = e + 1;
              let h = g + 1;
              return h;
            }
            """,
        :java => """
            class C {
              /**
               * Add seven, one step at a time.
               */
              int f(int x) {
                int a = x + 1;
                int b = a + 1;
                int c = b + 1;
                int d = c + 1;
                int e = d + 1;
                int g = e + 1;
                int h = g + 1;
                return h;
              }
            }
            """,
        :go => """
            package p

            // F adds seven, one step at a time.
            func F(x int) int {
            	a := x + 1
            	b := a + 1
            	c := b + 1
            	d := c + 1
            	e := d + 1
            	g := e + 1
            	h := g + 1
            	return h
            }
            """,
        :rust => """
            /// Add seven, one step at a time.
            fn f(x: i32) -> i32 {
                let a = x + 1;
                let b = a + 1;
                let c = b + 1;
                let d = c + 1;
                let e = d + 1;
                let g = e + 1;
                let h = g + 1;
                h
            }
            """,
        :c => """
            /**
             * Add seven, one step at a time.
             */
            int f(int x) {
              int a = x + 1;
              int b = a + 1;
              int c = b + 1;
              int d = c + 1;
              int e = d + 1;
              int g = e + 1;
              int h = g + 1;
              return h;
            }
            """,
        :cpp => """
            /**
             * Add seven, one step at a time.
             */
            int f(int x) {
              int a = x + 1;
              int b = a + 1;
              int c = b + 1;
              int d = c + 1;
              int e = d + 1;
              int g = e + 1;
              int h = g + 1;
              return h;
            }
            """,
        :php => """
            <?php
            /**
             * Add seven, one step at a time.
             */
            function f(\$x) {
              \$a = \$x + 1;
              \$b = \$a + 1;
              \$c = \$b + 1;
              \$d = \$c + 1;
              \$e = \$d + 1;
              \$g = \$e + 1;
              \$h = \$g + 1;
              return \$h;
            }
            """,
        :ruby => """
            # Add seven, one step at a time.
            def f(x)
              a = x + 1
              b = a + 1
              c = b + 1
              d = c + 1
              e = d + 1
              g = e + 1
              h = g + 1
              h
            end
            """,
        :bash => """
            # Add seven, one step at a time.
            f() {
              a=\$((\$1 + 1))
              b=\$((a + 1))
              c=\$((b + 1))
              d=\$((c + 1))
              e=\$((d + 1))
              g=\$((e + 1))
              h=\$((g + 1))
              echo \$h
            }
            """,
    )

    @test sort(collect(keys(documented))) == sort(collect(keys(Dendro.PROFILES)))
    @testset "$lang" for lang in sort(collect(keys(documented)))
        i = Fixtures.idx(lang, documented[lang])
        callables = [u for u in Dendro.units(i) if Dendro.is_callable(u, i)]
        @test !isempty(callables)
        for u in callables
            @test Dendro.function_length(u) >= Dendro.MIN_COMMENT_DENSITY_LINES
            @test Dendro.comment_density(u, i) == 0
        end
    end
end

@testitem "comment_density is an optional rule" tags = [:metrics] begin
    names(rules) = [r.name for r in rules]
    @test :comment_density in names(Dendro.OPTIONAL_RULES)
    @test :comment_density ∉ names(Dendro.BUILTIN_RULES)

    rule = only(r for r in Dendro.OPTIONAL_RULES if r.name == :comment_density)
    @test rule.kind === :scalar
    @test rule.scope === :callable
    @test rule.band == (30, 50)
end

@testitem "a switch costs one decision, not one per arm (c)" setup = [Fixtures] tags = [:metrics] begin
    # One switch of five arms. `cyclomatic` charges the base path plus five arms, six;
    # `cyclomatic_modified` charges the base path plus the switch, two.
    src = "int f(int x){ switch(x){ case 1: return 1; case 2: return 2; case 3: return 3; case 4: return 4; case 5: return 5; } return 0; }"
    i = Fixtures.idx(:c, src)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 6
    @test Dendro.cyclomatic_modified(u, i) == 2
end

@testitem "each switch costs its own decision (c)" setup = [Fixtures] tags = [:metrics] begin
    # Two switches of three arms. `cyclomatic` charges the base path plus six arms, seven;
    # `cyclomatic_modified` charges the base path plus one per switch, three.
    src = """
    int f(int x, int y) {
      switch (x) { case 1: a(); break; case 2: b(); break; case 3: c(); break; }
      switch (y) { case 1: d(); break; case 2: e(); break; case 3: g(); break; }
      return 0;
    }
    """
    i = Fixtures.idx(:c, src)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 7
    @test Dendro.cyclomatic_modified(u, i) == 3
end

@testitem "a default arm costs nothing either way" setup = [Fixtures] tags = [:metrics] begin
    # Whether a grammar spells the default branch as an ordinary arm (C) or gives it its
    # own node type (Go, JavaScript, PHP) decides whether `cyclomatic` charges for it.
    # `cyclomatic_modified` charges the switch, so the two readings of a default agree.
    cases = [
        (
            :c,
            "int f(int x){ switch(x){ case 1: a(); break; case 2: b(); break; } return 0; }",
            "int f(int x){ switch(x){ case 1: a(); break; case 2: b(); break; default: c(); } return 0; }",
        ),
        (
            :go,
            "func f(x int){ switch x { case 1: a(); case 2: b() } }",
            "func f(x int){ switch x { case 1: a(); case 2: b(); default: c() } }",
        ),
        (
            :javascript,
            "function f(x){ switch(x){ case 1: a(); break; case 2: b(); break; } }",
            "function f(x){ switch(x){ case 1: a(); break; case 2: b(); break; default: c(); } }",
        ),
        (
            :php,
            "<?php function f(\$x){ switch(\$x){ case 1: a(); break; case 2: b(); break; } }",
            "<?php function f(\$x){ switch(\$x){ case 1: a(); break; case 2: b(); break; default: c(); } }",
        ),
    ]
    @testset "$lang" for (lang, bare, defaulted) in cases
        readings = map((bare, defaulted)) do src
            i = Fixtures.idx(lang, src)
            return Dendro.cyclomatic_modified(only(Dendro.units(i)), i)
        end
        @test readings[1] == 2
        @test readings[2] == 2
    end
end

@testitem "a java fallthrough group costs the switch once" setup = [Fixtures] tags = [:metrics] begin
    # `case 1: case 2:` parses as two switch_labels, so `cyclomatic` charges both. The
    # switch is one dispatch however its labels are grouped, so `cyclomatic_modified` reads
    # the same number as it does for the arms written apart.
    shared = "class C {\n  int f(int x) {\n    switch (x) { case 1: case 2: return 1; default: return 0; }\n  }\n}\n"
    apart = "class C {\n  int f(int x) {\n    switch (x) { case 1: return 1; case 2: return 1; default: return 0; }\n  }\n}\n"

    readings = map((shared, apart)) do src
        i = Fixtures.idx(:java, src)
        u = only(Dendro.units(i))
        return (Dendro.cyclomatic(u, i), Dendro.cyclomatic_modified(u, i))
    end
    @test readings[1] == (4, 2)
    @test readings[2] == (4, 2)
end

@testitem "a rust match costs one decision (rust)" setup = [Fixtures] tags = [:metrics] begin
    # Five arms, the wildcard among them, since a `_ =>` is a match_arm like any other.
    src = "fn f(x: i32) -> i32 { match x { 1 => 1, 2 => 2, 3 => 3, 4 => 4, _ => 0 } }"
    i = Fixtures.idx(:rust, src)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 6
    @test Dendro.cyclomatic_modified(u, i) == 2
end

@testitem "a python match reads one higher than cyclomatic (python)" setup = [Fixtures] tags = [:metrics] begin
    # The one language where the modified count is the larger of the two. Python's
    # `case_clause` is not a `@decision`, so `cyclomatic` charges a match nothing at all
    # and subtracting its arms takes nothing back, leaving the switch's own charge. Pinned
    # here rather than fixed: putting `case_clause` in `@decision` would move every python
    # baseline, and that is a change with its own measurement to make.
    src = "def f(x):\n    match x:\n        case 1:\n            return 1\n        case 2:\n            return 2\n        case _:\n            return 0\n"
    i = Fixtures.idx(:python, src)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 1
    @test Dendro.cyclomatic_modified(u, i) == 2
end

@testitem "ruby and bash read a case without npath moving" setup = [Fixtures] tags = [:metrics] begin
    # Neither language wires npath's switch family, so `@switch_arm` and `@switch_stmt` are
    # the only place their case nodes are named. The npath readings are pinned beside the
    # complexity ones so widening `@switch` or `@case` to reach these two, which would send
    # npath through `switch_npath` and its zero-arm recursion, fails here.
    ruby = "def f(x)\n  case x\n  when 1 then 1\n  when 2 then 2\n  else 0\n  end\nend\n"
    bash = "f() {\n  case \"\$1\" in\n    a) echo 1 ;;\n    b) echo 2 ;;\n    *) echo 3 ;;\n  esac\n}\n"

    i = Fixtures.idx(:ruby, ruby)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 3
    @test Dendro.cyclomatic_modified(u, i) == 2
    @test Dendro.npath(u, i) == 1

    i = Fixtures.idx(:bash, bash)
    u = only(Dendro.units(i))
    @test Dendro.cyclomatic(u, i) == 4
    @test Dendro.cyclomatic_modified(u, i) == 2
    @test Dendro.npath(u, i) == 1
end

@testitem "julia reads the same number either way (julia)" setup = [Fixtures] tags = [:metrics] begin
    # Julia has no switch construct, so nothing is subtracted and nothing is added, and the
    # two metrics agree on every shape the language can write.
    sources = [
        "ternary" => "f(x) = x > 0 ? x : -x\n",
        "ifelseif" => "function f(x)\n    if x > 0\n        a(x)\n    elseif x < 0\n        b(x)\n    end\nend\n",
        "loops" => "function f(xs)\n    for x in xs\n        while x > 0\n            x -= 1\n        end\n    end\nend\n",
        "trycatch" => "function f(x)\n    try\n        a(x)\n    catch\n        b(x)\n    end\nend\n",
        "bools" => "function f(x, y)\n    return x > 0 && y > 0 || x == y\nend\n",
    ]
    @testset "$name" for (name, src) in sources
        i = Fixtures.idx(:julia, src)
        u = first(Dendro.units(i))
        @test Dendro.cyclomatic_modified(u, i) == Dendro.cyclomatic(u, i)
    end
end

@testitem "cyclomatic_modified is an optional rule" setup = [Fixtures] tags = [:metrics] begin
    names(rules) = [r.name for r in rules]
    @test :cyclomatic_modified in names(Dendro.OPTIONAL_RULES)
    @test :cyclomatic_modified ∉ names(Dendro.BUILTIN_RULES)

    rule = only(r for r in Dendro.OPTIONAL_RULES if r.name == :cyclomatic_modified)
    @test rule.band == Dendro.CYCLOMATIC_MODIFIED_BAND
    @test rule.band == only(r.band for r in Dendro.BUILTIN_RULES if r.name == :cyclomatic)
    # A variant reading of `cyclomatic` measures what `cyclomatic` measures, top-level code
    # among it, so it takes the same `:any` scope rather than a definition's.
    @test rule.scope === :any

    # A function past the high band fires only once the optionals are in the rule set.
    body = join(("    if x == $(k)\n        g($(k))\n    end" for k in 1:25), "\n")
    src = "function branchy(x)\n$(body)\n    return x\nend\n"
    mktempdir() do dir
        path = joinpath(dir, "branchy.jl")
        write(path, src)
        @test isempty(filter(f -> f.metric === :cyclomatic_modified, Dendro.analyze(path)))
        both = [Dendro.BUILTIN_RULES; Dendro.OPTIONAL_RULES]
        @test !isempty(filter(f -> f.metric === :cyclomatic_modified, Dendro.analyze(path; rules = both)))
    end
end
