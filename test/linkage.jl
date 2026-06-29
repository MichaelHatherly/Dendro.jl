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
end

@testitem "corpus symbols ignore locals inside a function body" setup = [Fixtures] tags = [:linkage] begin
    f = Fixtures.parsedfile(:julia, "function f(x)\n    tmp = x + 1\n    tmp\nend\n"; file = "f.jl")
    table = Dendro.corpus_symbols([f])

    # Only `f` is a corpus symbol. `tmp` is a local: its name binds inside the function
    # scope, not the file, so it is never visible to another file and never indexed.
    @test [d.name for d in table.defs] == ["f"]
end

@testitem "corpus symbols skip Python class methods" setup = [Fixtures] tags = [:linkage] begin
    f = Fixtures.parsedfile(:python, "def top():\n    return 1\nclass C:\n    def method(self):\n        return 2\n"; file = "m.py")
    table = Dendro.corpus_symbols([f])

    # `top` is a module-level function, importable by bare name. `method` is a class
    # attribute, reachable only as `C.method`, never by bare name, so it is not a corpus
    # symbol. `C` itself is a top-level name.
    @test sort([d.name for d in table.defs]) == ["C", "top"]
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
