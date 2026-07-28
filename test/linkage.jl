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

@testitem "unbound references carry the namespace a reference qualifies" setup = [Fixtures] tags = [:linkage] begin
    # A qualified reference resolves under `Namespace.name`, reading the namespace that
    # the name sits directly under: `Inner` out of `Outer.Inner.deep`. The qualifier's own
    # identifiers (`Outer`, `Inner`) stay bare, so only the name side is qualified.
    file = Fixtures.parsedfile(:julia, "f() = A.callee() + Outer.Inner.deep()\n"; file = "f.jl")
    names = Set(r.name for r in Dendro.unbound_references(file))
    @test "A.callee" in names
    @test "Inner.deep" in names
    @test "A" in names
    @test !("callee" in names)
end

@testitem "a module-nested definition is visible under its qualified name" setup = [Fixtures] tags = [:linkage] begin
    # Across a splice, a file-scope definition is visible by bare name and one inside a
    # `module` only by its qualified name, the two forms Julia's namespaces give.
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "spliced() = 1\nmodule A\nnested() = 2\nend\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "f() = 1\n"; file = "b.jl")
    files = [mod, a, b]
    visible = Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))
    names = keys(visible["b.jl"])
    @test "spliced" in names
    @test "A.nested" in names
    @test !("nested" in names)
end

@testitem "a spliced definition is visible under the module it splices into" setup = [Fixtures] tags = [:linkage] begin
    # `helper` sits at file scope in a file the `module M` body includes, so it joins M's
    # namespace: reachable bare, like any spliced name, and equally as `M.helper`.
    mod = Fixtures.parsedfile(:julia, "module M\ninclude(\"a.jl\")\ninclude(\"b.jl\")\nend\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "helper() = 1\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "f() = 1\n"; file = "b.jl")
    files = [mod, a, b]
    names = keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.jl"])
    @test "helper" in names
    @test "M.helper" in names
end

@testitem "a splice inside a submodule qualifies under that submodule" setup = [Fixtures] tags = [:linkage] begin
    # The namespace a file lands in is the one enclosing the `include` that pulled it in,
    # taken through the whole chain: `y.jl` is spliced into `X`, itself spliced into `M`.
    # Only the innermost name qualifies, the form a reference writes.
    mod = Fixtures.parsedfile(:julia, "module M\ninclude(\"x.jl\")\ninclude(\"b.jl\")\nend\n"; file = "mod.jl")
    x = Fixtures.parsedfile(:julia, "module X\ninclude(\"y.jl\")\nend\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "deep() = 1\n"; file = "y.jl")
    b = Fixtures.parsedfile(:julia, "f() = 1\n"; file = "b.jl")
    files = [mod, x, y, b]
    names = keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.jl"])
    @test "X.deep" in names
    @test !("M.deep" in names)
end

@testitem "a splice language that reaches no namespace keeps bare names" setup = [Fixtures] tags = [:linkage] begin
    # C splices a header the same way, but nothing in C reaches a definition by qualifying
    # a namespace, so its cross-file names carry no qualifier.
    main = Fixtures.parsedfile(:c, "#include \"a.c\"\n#include \"b.c\"\n"; file = "main.c")
    a = Fixtures.parsedfile(:c, "int helper(void) { return 1; }\n"; file = "a.c")
    b = Fixtures.parsedfile(:c, "int other(void) { return 2; }\n"; file = "b.c")
    files = [main, a, b]
    names = keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.c"])
    @test "helper" in names
    @test !any(contains('.'), names)
end

@testitem "a Ruby module body stays invisible across a require" setup = [Fixtures] tags = [:linkage] begin
    # Ruby splices and marks namespace regions, but reaching into one needs `Mod::name`,
    # which is untested, so a method inside a module is visible under neither form.
    main = Fixtures.parsedfile(:ruby, "require_relative 'a'\nrequire_relative 'b'\n"; file = "main.rb")
    a = Fixtures.parsedfile(:ruby, "def spliced\n  1\nend\nmodule A\n  def nested\n    2\n  end\nend\n"; file = "a.rb")
    b = Fixtures.parsedfile(:ruby, "def f\n  1\nend\n"; file = "b.rb")
    files = [main, a, b]
    names = keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.rb"])
    @test "spliced" in names
    @test !("nested" in names)
    @test !("A.nested" in names)
end

@testitem "a directory-model language keeps bare names" setup = [Fixtures] tags = [:linkage] begin
    # Go shares the same member resolver as a splice but reaches no namespace by
    # qualifying one, so a sibling's exported name stays bare.
    a = Fixtures.parsedfile(:go, "package p\n\nfunc Helper() int { return 1 }\n"; file = "p/a.go")
    b = Fixtures.parsedfile(:go, "package p\n\nfunc F() int { return 2 }\n"; file = "p/b.go")
    files = [a, b]
    names = keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["p/b.go"])
    @test "Helper" in names
    @test !any(contains('.'), names)
end

@testitem "a TypeScript import resolves a .js specifier to its source file" setup = [Fixtures] tags = [:linkage] begin
    # TypeScript's ESM output convention has a module specifier name the emitted `.js` file
    # while the source on disk is `.ts`, so the specifier matches no corpus path directly.
    # Resolution drops the compiled extension and tries the source extensions behind it;
    # without that, a corpus written this way resolves nothing across the file boundary.
    a = Fixtures.parsedfile(:typescript, "export function helper(): number {\n  return 1;\n}\n"; file = "a.ts")
    b = Fixtures.parsedfile(
        :typescript,
        "import { helper } from './a.js';\nexport function f(): number {\n  return helper();\n}\n";
        file = "b.ts",
    )
    files = [a, b]
    @test "helper" in keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.ts"])
end

@testitem "a JavaScript import still resolves a bare relative specifier" setup = [Fixtures] tags = [:linkage] begin
    # Dropping a compiled extension must not cost the extensionless form, which is what
    # JavaScript's own bundler convention writes.
    a = Fixtures.parsedfile(:javascript, "export function helper() {\n  return 1;\n}\n"; file = "a.js")
    b = Fixtures.parsedfile(
        :javascript,
        "import { helper } from './a';\nexport function f() {\n  return helper();\n}\n";
        file = "b.js",
    )
    files = [a, b]
    @test "helper" in keys(Dendro.corpus_visibility(files, Dendro.corpus_symbols(files))["b.js"])
end
