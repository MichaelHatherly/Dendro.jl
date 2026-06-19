@testitem "bindings link sibling functions through a shared file-local name" setup = [Fixtures] tags = [:bindings] begin
    src = """
    function helper(x)
        x + 1
    end
    function f(a)
        helper(a)
    end
    function g(b)
        helper(b)
    end
    """
    index = Fixtures.idx(:julia, src)
    pairs = Fixtures.binding_pairs(index)

    # Both calls to `helper`, from `f` and from `g`, resolve to the one definition on
    # line 1. Parameters (`a`, `b`, `x`) are not captured, so they add no binding, and
    # the `helper` definition itself is never bound as a reference. Exactly two.
    @test sort(pairs) == [("helper", 5) => ("helper", 1), ("helper", 8) => ("helper", 1)]
end

@testitem "bindings keep same-named locals in separate functions apart" setup = [Fixtures] tags = [:bindings] begin
    src = """
    function a()
        tmp = 1
        tmp + 1
    end
    function b()
        tmp = 2
        tmp + 2
    end
    """
    pairs = Fixtures.binding_pairs(Fixtures.idx(:julia, src))

    # Each `tmp` use binds to the local in its own function, never across. The
    # reference in `b` resolves to `b`'s `tmp`, not `a`'s.
    @test sort(pairs) == [("tmp", 3) => ("tmp", 2), ("tmp", 7) => ("tmp", 6)]
end

@testitem "bindings resolve const and type references, not free names" setup = [Fixtures] tags = [:bindings] begin
    src = """
    const FOO = 1
    struct Box
        v
    end
    use(x) = Box(x) + FOO + push!(x, FOO)
    """
    pairs = Fixtures.binding_pairs(Fixtures.idx(:julia, src))

    # `Box` and `FOO` resolve to their file-local definitions; `push!` is external,
    # so it stays unbound. `FOO` is referenced twice in `use`.
    @test sort(pairs) == [
        ("Box", 5) => ("Box", 2),
        ("FOO", 5) => ("FOO", 1),
        ("FOO", 5) => ("FOO", 1),
    ]
    @test !any(p -> first(first(p)) == "push!", pairs)
end

@testitem "bindings empty for a language with no scopes query" setup = [Fixtures] tags = [:bindings] begin
    @test Dendro.scopes_query_for(:python) === nothing
    index = Fixtures.idx(:python, "def f(x):\n    return f(x)\n")
    @test isempty(index.bindings)
end

@testitem "resolve_bindings! is type stable" setup = [Fixtures] tags = [:bindings] begin
    bindings = @inferred Fixtures.resolve(:julia, "helper(x) = x\nf(a) = helper(a)\n")
    @test bindings isa Dict{Dendro.NodeId, Dendro.NodeId}
    @test !isempty(bindings)
end
