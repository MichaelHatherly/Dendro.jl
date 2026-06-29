@testitem "function units (julia)" setup = [Fixtures] tags = [:units] begin
    using TreeSitter

    src = "function f(x)\n    x + 1\nend\nfunction g()\n    0\nend\n"
    units = Dendro.functions(Fixtures.idx(:julia, src))
    @test length(units) == 2
    @test TreeSitter.node_type(units[1].node) == "function_definition"
    @test units[1].firstline == 1
    @test units[1].lastline == 3
    @test units[2].firstline == 4
end

@testitem "short-form function units (julia)" setup = [Fixtures] tags = [:units] begin
    src = "f(x) = x + 1\ng(x)::Int = x\nh(x) where {T} = x\n"
    i = Fixtures.idx(:julia, src)
    units = Dendro.functions(i)
    @test length(units) == 3
    @test [Dendro.unit_name(u, i) for u in units] == ["f", "g", "h"]
    @test units[1].firstline == 1 && units[1].lastline == 1
    @test units[2].firstline == 2
    @test units[3].firstline == 3
end

@testitem "non-definition assignments are not units (julia)" setup = [Fixtures] tags = [:units] begin
    src = "x = 5\nk::T = nothing\na, b = t\n"
    @test isempty(Dendro.functions(Fixtures.idx(:julia, src)))
end

@testitem "qualified definitions are named by their final component (julia)" setup = [Fixtures] tags = [:units] begin
    name(src) = (i = Fixtures.idx(:julia, src); Dendro.unit_name(only(Dendro.functions(i)), i))

    # A qualified method is labelled by the method, not the module the lexical scan
    # reaches first.
    @test name("function Base.relpath(x)\n    x\nend\n") == "relpath"
    @test name("Missings.disallowmissing(df) = df\n") == "disallowmissing"
    @test name("function Base.show(io, x)\n    x\nend\n") == "show"
    # The qualified short form survives the `where`/`::T` wrappers too.
    @test name("CC.foo(x::T) where {T} = x\n") == "foo"

    # An unqualified definition is unchanged.
    @test name("function g(a, b)\n    a\nend\n") == "g"
    @test name("h(x) = x + 1\n") == "h"
end

@testitem "nested short-form def is its own unit (julia)" setup = [Fixtures] tags = [:units] begin
    src = "function outer(x)\n    inner(y) = y > 0 ? y : -y\n    return inner(x)\nend\n"
    i = Fixtures.idx(:julia, src)
    units = Dendro.functions(i)
    @test length(units) == 2
    outer = units[findfirst(u -> Dendro.unit_name(u, i) == "outer", units)]
    inner = units[findfirst(u -> Dendro.unit_name(u, i) == "inner", units)]
    # The nested def's ternary belongs to inner, so it never inflates outer.
    @test Dendro.cyclomatic(outer.node, i) == 1
    @test Dendro.nesting_depth(outer.node, i) == 0
    @test Dendro.cyclomatic(inner.node, i) == 2
end
