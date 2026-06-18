@testset "cyclomatic (julia)" begin
    p, prof = fixture(:julia)

    # A straight-line function has complexity 1.
    simple = "function f(x)\n    x + 1\nend\n"
    tree = parse(p, simple)
    u = only(Dendro.functions(tree, prof))
    @test Dendro.cyclomatic(u.node, prof, simple) == 1

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
    tree = parse(p, src)
    u = only(Dendro.functions(tree, prof))
    @test Dendro.cyclomatic(u.node, prof, src) == 9
end

@testset "cyclomatic on a short-form def (julia)" begin
    p, prof = fixture(:julia)
    src = "f(x) = x > 0 ? x : -x\n"
    u = only(Dendro.functions(parse(p, src), prof))
    @test Dendro.cyclomatic(u.node, prof, src) == 2   # base + ternary
    @test Dendro.function_length(u) == 1
end

@testset "nested functions do not inflate the enclosing unit (julia)" begin
    p, prof = fixture(:julia)

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
    units = Dendro.functions(parse(p, src), prof)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    inner = units[findfirst(u -> u.firstline != 1, units)]

    @test Dendro.cyclomatic(outer.node, prof, src) == 2   # base + for
    @test Dendro.nesting_depth(outer.node, prof) == 1      # the for only
    @test Dendro.cyclomatic(inner.node, prof, src) == 3   # base + if + &&
    @test Dendro.nesting_depth(inner.node, prof) == 1      # the if only
end

@testset "function_length (julia)" begin
    p, prof = fixture(:julia)
    src = "function f(x)\n    y = x + 1\n    return y\nend\n"
    tree = parse(p, src)
    u = only(Dendro.functions(tree, prof))
    @test Dendro.function_length(u) == 4
end

@testset "nesting_depth (julia)" begin
    p, prof = fixture(:julia)

    flat = "function f(x)\n    x + 1\nend\n"
    u = only(Dendro.functions(parse(p, flat), prof))
    @test Dendro.nesting_depth(u.node, prof) == 0

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
    u = only(Dendro.functions(parse(p, src), prof))
    @test Dendro.nesting_depth(u.node, prof) == 3
end

@testset "parameter_count (julia)" begin
    p, prof = fixture(:julia)

    u = only(Dendro.functions(parse(p, "function f(x, y, z)\n    x\nend\n"), prof))
    @test Dendro.parameter_count(u.node, prof) == 3

    u = only(Dendro.functions(parse(p, "function g()\n    0\nend\n"), prof))
    @test Dendro.parameter_count(u.node, prof) == 0

    # Type annotations on parameters still count as one parameter each.
    u = only(Dendro.functions(parse(p, "function h(a::Int, b)\n    a\nend\n"), prof))
    @test Dendro.parameter_count(u.node, prof) == 2
end

@testset "boolean_complexity (julia)" begin
    p, prof = fixture(:julia)

    flat = "function f(a)\n    return a\nend\n"
    u = only(Dendro.functions(parse(p, flat), prof))
    @test Dendro.boolean_complexity(u.node, prof, flat) == 0

    # Four operands joined by three operators is one expression of size 3.
    chain = "function f(a, b, c, d)\n    return a && b && c && d\nend\n"
    u = only(Dendro.functions(parse(p, chain), prof))
    @test Dendro.boolean_complexity(u.node, prof, chain) == 3

    # Two separate two-operator conditions: the max is 2, not 4.
    split = "function f(a, b, c, d, e, f)\n    if a && b && c\n        x = 1\n    end\n    if d && e && f\n        y = 2\n    end\nend\n"
    u = only(Dendro.functions(parse(p, split), prof))
    @test Dendro.boolean_complexity(u.node, prof, split) == 2
end

@testset "return_count (julia)" begin
    p, prof = fixture(:julia)

    src = "function f(x)\n    if x > 0\n        return 1\n    end\n    if x < 0\n        return 2\n    end\n    return 3\nend\n"
    u = only(Dendro.functions(parse(p, src), prof))
    @test Dendro.return_count(u.node, prof) == 3

    # A nested function's return belongs to the nested unit, not the enclosing one.
    nested = "function outer(x)\n    g = function (y)\n        return y\n    end\n    return x\nend\n"
    units = Dendro.functions(parse(p, nested), prof)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    @test Dendro.return_count(outer.node, prof) == 1
end

@testset "cognitive_complexity (julia)" begin
    p, prof = fixture(:julia)

    # Straight-line code breaks the flow nowhere, so it scores 0.
    simple = "function f(x)\n    x + 1\nend\n"
    u = only(Dendro.functions(parse(p, simple), prof))
    @test Dendro.cognitive_complexity(u.node, prof, simple) == 0

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
    u = only(Dendro.functions(parse(p, nested), prof))
    @test Dendro.cognitive_complexity(u.node, prof, nested) == 6

    # A boolean run adds one however long it is; an operator change starts a new
    # run. `a && b && c` is one run (if + 1 = 2); `a && b || c` is two (if + 2 = 3).
    onerun = "function f(a, b, c)\n    if a && b && c\n        g()\n    end\nend\n"
    u = only(Dendro.functions(parse(p, onerun), prof))
    @test Dendro.cognitive_complexity(u.node, prof, onerun) == 2

    tworun = "function f(a, b, c)\n    if a && b || c\n        g()\n    end\nend\n"
    u = only(Dendro.functions(parse(p, tworun), prof))
    @test Dendro.cognitive_complexity(u.node, prof, tworun) == 3

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
    u = only(Dendro.functions(parse(p, mixed), prof))
    @test Dendro.cognitive_complexity(u.node, prof, mixed) == 5

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
    units = Dendro.functions(parse(p, closure), prof)
    outer = units[findfirst(u -> u.firstline == 1, units)]
    # outer owns one for (1); the closure's if and && belong to the closure.
    @test Dendro.cognitive_complexity(outer.node, prof, closure) == 1
end

@testset "cognitive_complexity scores else-if chains flat" begin
    # SonarSource scores each condition in an if/else-if chain as a flat +1: the
    # continuation is not deeper nested code. `if/elseif/elseif` costs 3, not the
    # 1 + 2 + 2 a naive "decision plus nesting" reading would charge.
    jl = "function f(x)\n if x>0\n a()\n elseif x>1\n b()\n elseif x>2\n c()\n end\nend\n"
    pj, prof_jl = fixture(:julia)
    uj = only(Dendro.functions(parse(pj, jl), prof_jl))
    @test Dendro.cognitive_complexity(uj.node, prof_jl, jl) == 3
    # Each arm is still an independent path, so cyclomatic keeps counting them.
    @test Dendro.cyclomatic(uj.node, prof_jl, jl) == 4

    # Python's dedicated `elif_clause` scores the same way.
    py = "def f(x):\n    if x>0:\n        a()\n    elif x>1:\n        b()\n    elif x>2:\n        c()\n"
    pp, prof_py = fixture(:python)
    up = only(Dendro.functions(parse(pp, py), prof_py))
    @test Dendro.cognitive_complexity(up.node, prof_py, py) == 3

    # A decision genuinely nested under the chain still pays the nesting penalty:
    # the `for` sits one level deep inside the elseif body, so it costs +2.
    nested = "function f(x)\n if x>0\n a()\n elseif x>1\n for i in 1:x\n g(i)\n end\n end\nend\n"
    un = only(Dendro.functions(parse(pj, nested), prof_jl))
    @test Dendro.cognitive_complexity(un.node, prof_jl, nested) == 4  # if(1) + elseif(1) + for(2)
end

@testset "absolute severity bands" begin
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
