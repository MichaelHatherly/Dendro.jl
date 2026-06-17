@testset "python scalar metrics" begin
    p, prof = fixture(:python)
    big = "def f(x, y):\n    if x > 0 and y > 0:\n        for i in range(x):\n            while i > 0:\n                i -= 1\n    elif x < 0 or y < 0:\n        z = 1 if x > 0 else 2\n    try:\n        g()\n    except Exception as e:\n        h()\n    return [i for i in range(x) if i > 2]\n"
    u = only(Dendro.functions(parse(p, big), prof))
    # if(+1) and(+1) for(+1) while(+1) elif(+1) or(+1) ternary(+1) except(+1)
    @test Dendro.cyclomatic(u.node, prof, big) == 9
    @test Dendro.parameter_count(u.node, prof) == 2
    @test Dendro.nesting_depth(u.node, prof) == 3
end

@testset "python empty_body" begin
    p, prof = fixture(:python)

    # A pass-only body is an empty stub even though pass is a statement.
    u = only(Dendro.functions(parse(p, "def e():\n    pass\n"), prof))
    @test Dendro.empty_body(u.node, prof)

    body = only(Dendro.functions(parse(p, "def e():\n    return 1\n"), prof))
    @test !Dendro.empty_body(body.node, prof)
end

@testset "python empty_catches" begin
    p, prof = fixture(:python)

    # except: pass swallows the error.
    sw = "try:\n    f()\nexcept:\n    pass\n"
    @test length(Dendro.empty_catches(parse(p, sw), prof)) == 1

    handled = "try:\n    f()\nexcept Exception as e:\n    h(e)\n"
    @test isempty(Dendro.empty_catches(parse(p, handled), prof))
end

@testset "python stub_markers" begin
    p, prof = fixture(:python)
    st = "def s():\n    # TODO: x\n    return 1\n"
    @test length(Dendro.stub_markers(parse(p, st), prof, st)) == 1
end
