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

@testitem "bindings link a sibling call in every language" setup = [Fixtures] tags = [:bindings] begin
    @testset "$(case.lang)" for case in Fixtures.LANGUAGE_BINDING_CASES
        pairs = Fixtures.binding_pairs(Fixtures.idx(case.lang, case.src))
        # `f`'s call to `helper` resolves to the sibling definition: the cohesion edge.
        @test (("helper", case.ref) => ("helper", case.def)) in pairs
    end
end

@testitem "bindings define a C struct at its body, not at a forward declaration" setup = [Fixtures] tags = [:bindings] begin
    src = """
    struct client;
    int f(struct client *c);
    struct client { int fd; };
    """
    index = Fixtures.idx(:c, src)

    # `struct client;` and the parameter type in the prototype name the struct; only the
    # specifier with a body defines it, so both resolve to line 3.
    @test Fixtures.definitions(index) == [(:struct, "client", 3)]
    @test sort(Fixtures.binding_pairs(index)) == [("client", 1) => ("client", 3), ("client", 2) => ("client", 3)]
    # The scopes are the file and the struct body; a bodiless specifier opens none.
    @test length(index.scope_captures.scopes) == 2
end

@testitem "bindings define a C++ class at its body, not at a forward declaration" setup = [Fixtures] tags = [:bindings] begin
    src = """
    class Foo;
    struct Bar;
    void g(Foo *p, struct Bar *q);
    class Foo { int x; };
    struct Bar { int y; };
    """
    index = Fixtures.idx(:cpp, src)

    @test Fixtures.definitions(index) == [(:class, "Foo", 4), (:struct, "Bar", 5)]
    @test sort(Fixtures.binding_pairs(index)) == [
        ("Bar", 2) => ("Bar", 5), ("Bar", 3) => ("Bar", 5),
        ("Foo", 1) => ("Foo", 4), ("Foo", 3) => ("Foo", 4),
    ]
    @test length(index.scope_captures.scopes) == 3
end

@testitem "resolve_bindings! is type stable" setup = [Fixtures] tags = [:bindings] begin
    bindings = @inferred Fixtures.resolve(:julia, "helper(x) = x\nf(a) = helper(a)\n")
    @test bindings isa Dict{Dendro.NodeId, Dendro.NodeId}
    @test !isempty(bindings)
end
