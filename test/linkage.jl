@testitem "corpus symbols record top-level defs with their module path" setup = [Fixtures] tags = [:linkage] begin
    a = Fixtures.parsedfile(
        :julia,
        "module Outer\nconst TAU = 6.28\nf(x) = x\nmodule Inner\ng(y) = y\nend\nend\n";
        file = "a.jl",
    )
    b = Fixtures.parsedfile(:julia, "h(z) = z\n"; file = "b.jl")
    table = Dendro.corpus_symbols([a, b])

    # Every top-level function, type, and const becomes a corpus symbol keyed by its
    # enclosing module path. `g` sits in the nested `Inner`, so its path is two deep;
    # `h` is at file scope, so its path is empty. Module names themselves are not
    # symbols, only namespaces.
    rows = sort([(d.name, d.kind, d.module_path) for d in table.defs])
    @test rows == [
        ("TAU", :const, ["Outer"]),
        ("f", :function, ["Outer"]),
        ("g", :function, ["Outer", "Inner"]),
        ("h", :function, String[]),
    ]

    # The name index keys on (language, module path, name) so a lookup is scoped to the
    # module a reference can see, and two `g`s in different modules never collide.
    gi = only(table.by_name[(:julia, ["Outer", "Inner"], "g")])
    @test table.defs[gi].file == "a.jl"
    @test !haskey(table.by_name, (:julia, String[], "g"))
end

@testitem "corpus symbols ignore locals inside a function body" setup = [Fixtures] tags = [:linkage] begin
    f = Fixtures.parsedfile(:julia, "function f(x)\n    tmp = x + 1\n    tmp\nend\n"; file = "f.jl")
    table = Dendro.corpus_symbols([f])

    # Only `f` is a corpus symbol. `tmp` is a local: its name binds inside the function
    # scope, not the file, so it is never visible to another file and never indexed.
    @test [d.name for d in table.defs] == ["f"]
end

@testitem "unbound references carry cross-file names and their unit" setup = [Fixtures] tags = [:linkage] begin
    file = Fixtures.parsedfile(:julia, "helper(x) = x\nf(a) = helper(push!(a, 1))\n"; file = "f.jl")
    refs = Dendro.unbound_references(file)
    names = Set(r.name for r in refs)

    # `helper` resolves to its sibling definition, so it binds in-file and is absent.
    # `push!` has no in-file definition: it is the cross-file reference the corpus graph
    # will resolve, reported inside unit 2 (`f`, on line 2).
    @test "push!" in names
    @test !("helper" in names)
    pushref = only(filter(r -> r.name == "push!", refs))
    @test file.index.functions[pushref.unit].firstline == 2
end
