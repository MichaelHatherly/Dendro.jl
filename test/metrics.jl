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

@testset "absolute severity bands" begin
    @test Dendro.severity(:cyclomatic, 10) == :ok
    @test Dendro.severity(:cyclomatic, 11) == :warn
    @test Dendro.severity(:cyclomatic, 21) == :high
    @test Dendro.severity(:nesting_depth, 3) == :ok
    @test Dendro.severity(:nesting_depth, 6) == :high
    @test Dendro.severity(:parameter_count, 5) == :warn
    @test Dendro.severity(:function_length, 120) == :high
end
