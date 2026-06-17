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

@testset "absolute severity bands" begin
    # Classification against a (warn, high) band.
    @test Dendro.severity(10, (11, 21)) == :ok
    @test Dendro.severity(11, (11, 21)) == :warn
    @test Dendro.severity(21, (11, 21)) == :high

    # The built-in bands the classification runs against.
    band(name) = only(r.band for r in Dendro.BUILTIN_RULES if r.name == name)
    @test band(:cyclomatic) == (11, 21)
    @test band(:nesting_depth) == (4, 6)
    @test band(:parameter_count) == (5, 8)
    @test band(:function_length) == (50, 100)
end
