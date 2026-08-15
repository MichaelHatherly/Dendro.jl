@testitem "function units (julia)" setup = [Fixtures] tags = [:units] begin
    using TreeSitter

    src = "function f(x)\n    x + 1\nend\nfunction g()\n    0\nend\n"
    units = Dendro.units(Fixtures.idx(:julia, src))
    @test length(units) == 2
    @test TreeSitter.node_type(Dendro.unit_node(units[1])) == "function_definition"
    @test units[1].firstline == 1
    @test units[1].lastline == 3
    @test units[2].firstline == 4
end

@testitem "short-form function units (julia)" setup = [Fixtures] tags = [:units] begin
    src = "f(x) = x + 1\ng(x)::Int = x\nh(x) where {T} = x\n"
    i = Fixtures.idx(:julia, src)
    units = Dendro.units(i)
    @test length(units) == 3
    @test [Dendro.unit_name(u, i) for u in units] == ["f", "g", "h"]
    @test units[1].firstline == 1 && units[1].lastline == 1
    @test units[2].firstline == 2
    @test units[3].firstline == 3
end

@testitem "non-definition assignments are not callable units (julia)" setup = [Fixtures] tags = [:units] begin
    src = "x = 5\nk::T = nothing\na, b = t\n"
    i = Fixtures.idx(:julia, src)
    # They are top-level code, so they are a unit; none of them is a definition.
    @test !any(u -> Dendro.is_callable(u, i), Dendro.units(i))
end

@testitem "qualified definitions are named by their final component (julia)" setup = [Fixtures] tags = [:units] begin
    name(src) = (i = Fixtures.idx(:julia, src); Dendro.unit_name(only(Dendro.units(i)), i))

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

@testitem "units are named by their defining name across languages" setup = [Fixtures] tags = [:units] begin
    name(lang, src) = (i = Fixtures.idx(lang, src); Dendro.unit_name(only(Dendro.units(i)), i))

    # Go: a method's receiver variable precedes its name in the lexical scan.
    @test name(:go, "func (r *T) Foo() {}\n") == "Foo"
    @test name(:go, "func Bar(x int) {}\n") == "Bar"

    # Java: a leading annotation precedes the method or constructor name.
    @test name(:java, "class C { @Deprecated public int foo(int x) { return 0; } }\n") == "foo"
    @test name(:java, "class C { @Deprecated public C() {} }\n") == "C"

    # C: a return-type token or storage-class macro precedes the name; the name is the
    # identifier in the declarator, found through a pointer-return wrapper.
    @test name(:c, "void f(int x) {}\n") == "f"
    @test name(:c, "char *g(void) { return 0; }\n") == "g"
    @test name(:c, "REDIS_STATIC void _quicklistInsert(int x) {}\n") == "_quicklistInsert"

    # C++: a member, a qualified `Class::method` (named by its final component), a
    # destructor, and an operator each name the unit by its declarator.
    @test name(:cpp, "struct S { void m() {} };\n") == "m"
    @test name(:cpp, "int Foo::bar(int x) { return x; }\n") == "bar"
    @test name(:cpp, "struct S { ~S() {} };\n") == "~S"
    @test name(:cpp, "struct S { bool operator==(int x) { return true; } };\n") == "operator=="

    # JS/TS: a named function or method names directly; an arrow bound to a name takes
    # that name from its binder, a sibling outside the arrow's own subtree.
    @test name(:javascript, "function g(x) {}\n") == "g"
    @test name(:javascript, "class C { foo() {} }\n") == "foo"
    @test name(:javascript, "const f = key => key.toLowerCase();\n") == "f"
    @test name(:typescript, "const f = (key: string) => key;\n") == "f"

    # An anonymous arrow callback carries no name; it stays labelled by the first
    # identifier the lexical scan reaches, its parameter.
    @test name(:javascript, "arr.map(key => key.x);\n") == "key"
end

@testitem "nested short-form def is its own unit (julia)" setup = [Fixtures] tags = [:units] begin
    src = "function outer(x)\n    inner(y) = y > 0 ? y : -y\n    return inner(x)\nend\n"
    i = Fixtures.idx(:julia, src)
    units = Dendro.units(i)
    @test length(units) == 2
    outer = units[findfirst(u -> Dendro.unit_name(u, i) == "outer", units)]
    inner = units[findfirst(u -> Dendro.unit_name(u, i) == "inner", units)]
    # The nested def's ternary belongs to inner, so it never inflates outer.
    @test Dendro.cyclomatic(outer, i) == 1
    @test Dendro.nesting_depth(outer, i) == 0
    @test Dendro.cyclomatic(inner, i) == 2
end

@testitem "a run of several nodes is not a callable unit" setup = [Fixtures] tags = [:units] begin
    using TreeSitter

    src = "x = 1\nfunction f(y)\n    y\nend\nz = x + 1\n"
    i = Fixtures.idx(:julia, src)
    top = filter(u -> !Dendro.is_callable(u, i), Dendro.units(i))
    callable = only(filter(u -> Dendro.is_callable(u, i), Dendro.units(i)))

    # The definition splits the top-level code either side of it into two runs.
    @test [length(t.nodes) for t in top] == [1, 1]
    @test length(callable.nodes) == 1
end

@testitem "a callable-scoped rule skips top-level code" setup = [Fixtures] tags = [:units] begin
    using TreeSitter

    # Long enough to breach `function_length`, and branching enough to breach
    # `cyclomatic`, so a rule that fires says something about scope and not size.
    body = join(("a$(n) = $(n) > 1 ? $(n) : 0" for n in 1:120), "\n")
    src = body * "\n"
    tree = Dendro.parse_source(Dendro.parser_for(:julia), src)
    i = Dendro.build_index(tree, :julia, src, Dendro.query_for(:julia), Dendro.scopes_query_for(:julia))
    top = Dendro.Unit(
        TreeSitter.Node[
            c for c in TreeSitter.named_children(TreeSitter.root(tree))
                if !(c in i.comment)
        ], 1, 120
    )

    fired(name) = begin
        rule = only(filter(r -> r.name === name, Dendro.BUILTIN_RULES))
        out = Dendro.Finding[]
        Dendro.unit_findings!(out, Dendro.Scan(i, "top.jl"; rules = [rule]), top)
        !isempty(out)
    end

    # Length measures the distance to a boundary an author drew, and top-level code
    # has none; complexity measures the code itself either way.
    @test !fired(:function_length)
    @test !fired(:parameter_count)
    @test fired(:cyclomatic)
end

@testitem "a callable unit still reads every rule" setup = [Fixtures] tags = [:units] begin
    src = "function f(a, b, c, d, e, g)\n" * join(("    x$(n) = $(n)" for n in 1:120), "\n") * "\nend\n"
    i = Fixtures.idx(:julia, src)
    unit = only(Dendro.units(i))
    out = Dendro.Finding[]
    Dendro.unit_findings!(out, Dendro.Scan(i, "f.jl"; rules = Dendro.BUILTIN_RULES), unit)
    fired = Set(f.metric for f in out)
    @test :function_length in fired
    @test :parameter_count in fired
end

@testitem "top-level code becomes a unit, in runs between definitions" setup = [Fixtures] tags = [:units] begin
    src = """
    using X
    a = 1
    function f(y)
        y
    end
    b = 2
    struct S end
    c = 3
    """
    i = Fixtures.idx(:julia, src)
    us = Dendro.units(i)
    kinds = [Dendro.is_callable(u, i) for u in us]
    spans = [(u.firstline, u.lastline) for u in us]

    # Source order, and the run breaks at the definition and at the declaration rather
    # than straddling them.
    @test spans == [(1, 2), (3, 5), (6, 6), (8, 8)]
    @test kinds == [false, true, false, false]
    @test length(us[1].nodes) == 2
end

@testitem "a module body holds top-level code" setup = [Fixtures] tags = [:units] begin
    src = "module M\nusing X\nconst A = 1\nf(x) = x\nend\n"
    i = Fixtures.idx(:julia, src)
    top = filter(u -> !Dendro.is_callable(u, i), Dendro.units(i))
    # The module itself is a declaration, so it is not folded into a run; its body is
    # where the statements are read.
    @test [(u.firstline, u.lastline) for u in top] == [(2, 3)]
end

@testitem "a language with no toplevel capture grows no top-level units" setup = [Fixtures] tags = [:units] begin
    i = Fixtures.idx(:python, "import os\nx = 1\ndef f():\n    return x\n")
    @test all(u -> Dendro.is_callable(u, i), Dendro.units(i))
end

@testitem "def_name captures are keyed by the node holding them" setup = [Fixtures] tags = [:units] begin
    # `binder_def_name` reads this map rather than scanning a parent's children. A
    # top-level definition's parent is the whole file, so the scan cost every unit a walk
    # over every other top-level node.
    i = Fixtures.idx(:javascript, "const f = key => key;\nconst g = (a, b) => a + b;\n")
    units = Dendro.units(i)
    @test [Dendro.unit_name(u, i) for u in units] == ["f", "g"]

    # One entry per binder, keyed by the binder rather than by the file, so two arrows
    # declared side by side do not resolve to each other's name.
    binders = [
        Dendro.nodeid(Dendro.TreeSitter.parent(Dendro.unit_node(u))) for u in units
    ]
    @test length(Set(binders)) == 2
    @test all(haskey(i.def_name_parents, b) for b in binders)

    # A language whose query tags no `@def_name` carries no entries, and its units are
    # named by the lexical scan alone.
    bash = Fixtures.idx(:bash, "f() {\n  echo 1\n}\n")
    @test isempty(bash.def_name_parents)
    @test Dendro.unit_name(only(Dendro.units(bash)), bash) == "f"
end
