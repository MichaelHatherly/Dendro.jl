@testitem "python scalar metrics" setup = [Fixtures] tags = [:python] begin
    big = "def f(x, y):\n    if x > 0 and y > 0:\n        for i in range(x):\n            while i > 0:\n                i -= 1\n    elif x < 0 or y < 0:\n        z = 1 if x > 0 else 2\n    try:\n        g()\n    except Exception as e:\n        h()\n    return [i for i in range(x) if i > 2]\n"
    i = Fixtures.idx(:python, big)
    u = only(Dendro.functions(i))
    # if(+1) and(+1) for(+1) while(+1) elif(+1) or(+1) ternary(+1) except(+1)
    @test Dendro.cyclomatic(u.node, i) == 9
    @test Dendro.parameter_count(u.node, i) == 2
    @test Dendro.nesting_depth(u.node, i) == 3
end

@testitem "python empty_body" setup = [Fixtures] tags = [:python] begin
    # A pass-only body is an empty stub even though pass is a statement.
    i = Fixtures.idx(:python, "def e():\n    pass\n")
    @test Dendro.empty_body(only(Dendro.functions(i)).node, i)

    i = Fixtures.idx(:python, "def e():\n    return 1\n")
    @test !Dendro.empty_body(only(Dendro.functions(i)).node, i)
end

@testitem "python empty_catches" setup = [Fixtures] tags = [:python] begin
    # except: pass swallows the error.
    sw = "try:\n    f()\nexcept:\n    pass\n"
    @test length(Dendro.empty_catches(Fixtures.idx(:python, sw))) == 1

    handled = "try:\n    f()\nexcept Exception as e:\n    h(e)\n"
    @test isempty(Dendro.empty_catches(Fixtures.idx(:python, handled)))
end

@testitem "python stub_markers" setup = [Fixtures] tags = [:python] begin
    st = "def s():\n    # TODO: x\n    return 1\n"
    @test length(Dendro.stub_markers(Fixtures.idx(:python, st))) == 1
end
