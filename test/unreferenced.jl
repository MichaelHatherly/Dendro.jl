# Reachability from the public surface. Each case builds a tiny corpus and checks which
# private definitions the dead-code pass reaches. The cross-file cases splice files
# together so a reference leaves its file, exercising `corpus_references`. The
# `Fixtures.unref_sites` helper returns the (file, unit) sites flagged.

@testitem ":unreferenced leaves a privately-called helper alone" setup = [Fixtures] tags = [:unreferenced] begin
    # `entry` is public; it calls `helper` within the file. The within-file binding edge
    # carries reachability to `helper`, so neither is flagged.
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = helper()\nhelper() = 1\n"; file = "a.jl")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced leaves a public definition with no caller alone" setup = [Fixtures] tags = [:unreferenced] begin
    # Declared public, so a root: nothing inside the corpus need reference it.
    a = Fixtures.parsedfile(:julia, "export lonely\nlonely() = 1\n"; file = "a.jl")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced leaves an exported TypeScript type alias alone" setup = [Fixtures] tags = [:unreferenced] begin
    a = Fixtures.parsedfile(:typescript, "export type Row = { a: number };\n"; file = "a.ts")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced flags a private definition nothing names" setup = [Fixtures] tags = [:unreferenced] begin
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = 1\ndead() = 2\n"; file = "a.jl")
    f = only(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
    @test f.metric == :unreferenced
    @test f.absolute == :high
    @test first(f.locations).file == "a.jl"
    @test first(f.locations).line == 3
    @test first(f.locations).unit == "dead"
end

@testitem ":unreferenced flags a dead mutually-recursive private cluster" setup = [Fixtures] tags = [:unreferenced] begin
    # `foo` and `bar` reference each other, so neither has in-degree zero, but no path
    # reaches them from a root. Reachability catches what a caller count misses.
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = 1\nfoo() = bar()\nbar() = foo()\n"; file = "a.jl")
    @test Fixtures.unref_sites([a]) == Set([("a.jl", "foo"), ("a.jl", "bar")])
end

@testitem ":unreferenced flags a dead cluster split across files" setup = [Fixtures] tags = [:unreferenced] begin
    # The mutual recursion crosses the splice: `foo` in a.jl calls `bar` in b.jl and back.
    # Neither is public nor reached from top level, so both are dead. `entry`/`shared`
    # stay live, reached from the public root through a cross-file edge.
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = shared()\nfoo() = bar()\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "shared() = 1\nbar() = foo()\n"; file = "b.jl")
    @test Fixtures.unref_sites([mod, a, b]) == Set([("a.jl", "foo"), ("b.jl", "bar")])
end

@testitem ":unreferenced follows a reference qualified by its module" setup = [Fixtures] tags = [:unreferenced] begin
    # A definition inside a `module` never joins the includer's namespace, so the only
    # way to reach it is qualified. `entry` is the public root; it names `B.wrapper`,
    # which names `A.callee`. Both submodule definitions are live.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\ninclude(\"a.jl\")\ninclude(\"b.jl\")\nentry() = B.wrapper()\nend\n";
        file = "mod.jl",
    )
    a = Fixtures.parsedfile(:julia, "module A\ncallee() = 1\nend\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "module B\nwrapper() = A.callee()\nend\n"; file = "b.jl")
    @test isempty(Fixtures.unref_sites([mod, a, b]))
end

@testitem ":unreferenced flags a module-nested definition nothing qualifies" setup = [Fixtures] tags = [:unreferenced] begin
    # `A.callee` is reached; `A.dead` shares its module but nothing names it. Qualified
    # resolution carries liveness to the name written, not to the whole module.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\ninclude(\"a.jl\")\nentry() = A.callee()\nend\n";
        file = "mod.jl",
    )
    a = Fixtures.parsedfile(:julia, "module A\ncallee() = 1\ndead() = 2\nend\n"; file = "a.jl")
    @test Fixtures.unref_sites([mod, a]) == Set([("a.jl", "dead")])
end

@testitem ":unreferenced reads a full module path as a qualifier" setup = [Fixtures] tags = [:unreferenced] begin
    # A nested module is reached by either the whole path or its innermost name, the two
    # forms Julia accepts once the outer module is in scope.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\ninclude(\"a.jl\")\nentry() = Outer.Inner.deep() + Inner.shallow()\nend\n";
        file = "mod.jl",
    )
    a = Fixtures.parsedfile(
        :julia,
        "module Outer\nmodule Inner\ndeep() = 1\nshallow() = 2\nend\nend\n";
        file = "a.jl",
    )
    @test isempty(Fixtures.unref_sites([mod, a]))
end

@testitem ":unreferenced follows a reference qualified by the module a file splices into" setup = [Fixtures] tags = [:unreferenced] begin
    # `helper` sits at file scope in a file `module M` includes, so it joins M's namespace
    # and `M.helper` reaches it. That is the form a submodule writes to call back out.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\ninclude(\"a.jl\")\ninclude(\"b.jl\")\nentry() = B.wrapper()\nend\n";
        file = "mod.jl",
    )
    a = Fixtures.parsedfile(:julia, "helper() = 1\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "module B\nwrapper() = M.helper()\nend\n"; file = "b.jl")
    @test isempty(Fixtures.unref_sites([mod, a, b]))
end

@testitem ":unreferenced follows a bare reference back into the module body" setup = [Fixtures] tags = [:unreferenced] begin
    # `SCALE` sits in `M`'s own body and `a.jl` is spliced into `M`, so the bare name
    # `a.jl` writes is the one that reaches it. Resolving only the qualified form would
    # call a const the corpus reads on every call dead.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\nconst SCALE = 2\ninclude(\"a.jl\")\nend\n";
        file = "mod.jl",
    )
    a = Fixtures.parsedfile(:julia, "entry(x) = x * SCALE\n"; file = "a.jl")
    @test isempty(Fixtures.unref_sites([mod, a]))
end

@testitem ":unreferenced reads a nested splice as the innermost module" setup = [Fixtures] tags = [:unreferenced] begin
    # `y.jl` is spliced into `X`, itself spliced into `M`, so `deep` answers to `X.deep`.
    mod = Fixtures.parsedfile(
        :julia,
        "module M\npublic entry\ninclude(\"x.jl\")\nentry() = X.deep()\nend\n";
        file = "mod.jl",
    )
    x = Fixtures.parsedfile(:julia, "module X\ninclude(\"y.jl\")\nend\n"; file = "x.jl")
    y = Fixtures.parsedfile(:julia, "deep() = 1\n"; file = "y.jl")
    @test isempty(Fixtures.unref_sites([mod, x, y]))
end

@testitem ":unreferenced does not read a field access as a bare reference" setup = [Fixtures] tags = [:unreferenced] begin
    # `row.total` reads a field of a value. Its name happens to match a definition in
    # another file, which it has nothing to do with, so that definition stays dead.
    mod = Fixtures.parsedfile(:julia, "include(\"a.jl\")\ninclude(\"b.jl\")\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "total() = 1\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "read_total(row) = row.total\nread_total(nothing)\n"; file = "b.jl")
    @test Fixtures.unref_sites([mod, a, b]) == Set([("a.jl", "total")])
end

@testitem ":unreferenced leaves a definition reached from top-level code alone" setup = [Fixtures] tags = [:unreferenced] begin
    # The bare `main()` runs unconditionally, so `main` is a root even with no export;
    # `work` is reached through it.
    a = Fixtures.parsedfile(:julia, "main()\nmain() = work()\nwork() = 1\n"; file = "a.jl")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced respects dendro-ignore" setup = [Fixtures] tags = [:unreferenced] begin
    src = "export keep\nkeep() = 1\n# dendro-ignore: unreferenced\ndead() = 2\n"
    i = Fixtures.idx(:julia, src)
    directives = Dendro.suppressions(i; file = "a.jl")
    a = Fixtures.parsedfile(:julia, src; file = "a.jl", directives = directives)
    hit = only(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
    @test hit.suppressed
end

@testitem ":unreferenced keeps every overload of a referenced name alive" setup = [Fixtures] tags = [:unreferenced] begin
    # `entry` is a root and names `render`; two `render` methods exist. A within-file
    # reference binds lexically to one, but name resolution cannot tell overloads apart, so
    # reaching one reaches all. Without that, the unbound overload would be a false positive.
    a = Fixtures.parsedfile(:julia, "export entry\nentry() = render(1)\nrender(x::Int) = 1\nrender(x::String) = 2\n"; file = "a.jl")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced keeps a method defined in another file of the module alive" setup = [Fixtures] tags = [:unreferenced] begin
    # `render` has a method in a.jl and one in b.jl, both spliced into `M`. The call in
    # `entry` binds lexically to the a.jl method, but the b.jl one is the same function, so
    # reaching one reaches both.
    mod = Fixtures.parsedfile(:julia, "module M\nexport entry\ninclude(\"a.jl\")\ninclude(\"b.jl\")\nend\n"; file = "mod.jl")
    a = Fixtures.parsedfile(:julia, "entry() = render(1)\nrender(x::Int) = 1\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "render(x::String) = 2\n"; file = "b.jl")
    @test isempty(Fixtures.unref_sites([mod, a, b]))

    # A same-named function in another module, which the call cannot name, stays dead.
    other = Fixtures.parsedfile(:julia, "module Other\nrender(x::Float64) = 3\nend\n"; file = "other.jl")
    @test Fixtures.unref_sites([mod, a, b, other]) == Set([("other.jl", "render")])
end

@testitem ":unreferenced roots a macro-consumed definition" setup = [Fixtures] tags = [:unreferenced] begin
    # `@GET` consumes `handler`: a route macro registers it, so no in-corpus call reaches it,
    # yet it is a live entry point. It roots the search, and `helper`, called only from it,
    # stays live through the within-file edge.
    a = Fixtures.parsedfile(:julia, "@GET \"/x\" function handler(req)\n    helper()\nend\nhelper() = 1\n"; file = "a.jl")
    @test isempty(Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a])))
end

@testitem ":unreferenced flags a definition under a transparent macro" setup = [Fixtures] tags = [:unreferenced] begin
    # `@inline` annotates ordinary code rather than handing it to external machinery, so it
    # does not root. An inlined function nothing names is still dead.
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = 1\n@inline dead() = 2\n"; file = "a.jl")
    @test Fixtures.unref_sites([a]) == Set([("a.jl", "dead")])
end

@testitem ":unreferenced does not root a helper nested in a macro block" setup = [Fixtures] tags = [:unreferenced] begin
    # The macro consumes the `begin` block, not the definition inside it: crossing a body
    # scope means the wrapper does not consume the definition itself, so a dead helper nested
    # in `@testitem begin ... end` is still flagged.
    a = Fixtures.parsedfile(:julia, "@testitem \"t\" begin\n    inner() = 1\nend\n"; file = "a.jl")
    @test Fixtures.unref_sites([a]) == Set([("a.jl", "inner")])
end

@testitem ":unreferenced flags a dead private type and const" setup = [Fixtures] tags = [:unreferenced] begin
    # Reachability covers every top-level definition, not only functions: a struct and a
    # const nothing names, neither exported, are dead.
    a = Fixtures.parsedfile(:julia, "export keep\nkeep() = 1\nstruct Dead end\nconst GONE = 1\n"; file = "a.jl")
    @test Fixtures.unref_sites([a]) == Set([("a.jl", "Dead"), ("a.jl", "GONE")])
end

@testitem ":unreferenced reads Go capitalisation as the public surface" setup = [Fixtures] tags = [:unreferenced] begin
    # `Entry` is exported (capitalised), so a root; it calls `helper`, which stays live.
    # `dead` is private and unreached.
    src = "package m\nfunc Entry() int { return helper() }\nfunc helper() int { return 1 }\nfunc dead() int { return 2 }\n"
    g = Fixtures.parsedfile(:go, src; file = "m.go")
    @test Fixtures.unref_sites([g]) == Set([("m.go", "dead")])
end

@testitem ":unreferenced reads a Python leading underscore as private" setup = [Fixtures] tags = [:unreferenced] begin
    src = "def public_fn():\n    return 1\ndef _dead():\n    return 2\n"
    p = Fixtures.parsedfile(:python, src; file = "m.py")
    @test Fixtures.unref_sites([p]) == Set([("m.py", "_dead")])
end

@testitem ":unreferenced reaches a private Python name through an import" setup = [Fixtures] tags = [:unreferenced] begin
    # `main` imports and calls `_used`; the cross-file import edge keeps the underscore-
    # private name alive. `_dead` is private and no file imports it, so it is flagged. This
    # exercises cross-file resolution for the import model the splice cases cover for Julia.
    main = Fixtures.parsedfile(:python, "from helper import _used\n_used()\n"; file = "main.py")
    helper = Fixtures.parsedfile(:python, "def _used():\n    return 1\ndef _dead():\n    return 2\n"; file = "helper.py")
    @test Fixtures.unref_sites([main, helper]) == Set([("helper.py", "_dead")])
end

@testitem ":unreferenced reads a JS export list as the public surface" setup = [Fixtures] tags = [:unreferenced] begin
    src = "export function keep() { return used(); }\nfunction used() { return 1; }\nfunction dead() { return 2; }\n"
    j = Fixtures.parsedfile(:javascript, src; file = "m.js")
    @test Fixtures.unref_sites([j]) == Set([("m.js", "dead")])
end

@testitem ":unreferenced reads an exported TypeScript interface as public" setup = [Fixtures] tags = [:unreferenced] begin
    # `Shape` is exported and named only in type positions elsewhere: an `import type`, an
    # `implements` clause, a generic argument. It is public, and the reference resolves.
    shapes = Fixtures.parsedfile(:typescript, "export interface Shape { size: number }\n"; file = "shapes.ts")
    src = "import type { Shape } from './shapes';\nexport class Box implements Shape { size = 1; }\nexport const all: Array<Shape> = [];\n"
    use = Fixtures.parsedfile(:typescript, src; file = "use.ts")
    files = [shapes, use]
    @test isempty(Fixtures.unref_sites(files))
    table = Dendro.corpus_symbols(files)
    reached = Set(table.defs[di].name for r in Dendro.resolve_linkage(files, table).references for di in r.candidates)
    @test "Shape" in reached

    # A private interface lives through a type annotation in its own file, and one nothing
    # names is dead.
    local_src = "interface Options { n: number }\ninterface Unused { m: number }\nexport function make(o: Options): number { return o.n; }\n"
    m = Fixtures.parsedfile(:typescript, local_src; file = "m.ts")
    @test Fixtures.unref_sites([m]) == Set([("m.ts", "Unused")])
end

@testitem ":unreferenced reads an object-literal method as a property" setup = [Fixtures] tags = [:unreferenced] begin
    # `start` is a key of the exported object, which a framework calls through the object.
    # A property key binds no file-scope name, so it is never a definition to judge, and
    # `boot`, which it calls, is live.
    src = "export const hooks = {\n  start() { boot(); },\n};\nfunction boot() { }\nfunction dead() { }\n"
    t = Fixtures.parsedfile(:typescript, src; file = "hooks.ts")
    @test Fixtures.unref_sites([t]) == Set([("hooks.ts", "dead")])
end

@testitem ":unreferenced roots a Python definition a decorator registers" setup = [Fixtures] tags = [:unreferenced] begin
    # `@app.route` hands `_handler` to a route table, and `_helper` lives through it. A
    # wrapper that only annotates ordinary code, `functools.cache`, roots nothing.
    src = "@app.route('/')\ndef _handler():\n    return _helper()\ndef _helper():\n    return 1\n@functools.cache\ndef _dead():\n    return 2\n@register\nclass _Plugin:\n    pass\n"
    p = Fixtures.parsedfile(:python, src; file = "m.py")
    @test Fixtures.unref_sites([p]) == Set([("m.py", "_dead")])
end

@testitem ":unreferenced roots a Java method or class an annotation registers" setup = [Fixtures] tags = [:unreferenced] begin
    # A lifecycle or injection annotation hands its method to the framework. A `java.lang`
    # annotation only annotates, so the method it marks is still judged.
    src = "public class C {\n  @PostConstruct\n  private void init() { }\n  @javax.inject.Inject private void wire(int a) { }\n  @SuppressWarnings(\"x\")\n  private void dead() { }\n}\n@Component\nclass Registered { }\nclass Unused { }\n"
    j = Fixtures.parsedfile(:java, src; file = "C.java")
    @test Fixtures.unref_sites([j]) == Set([("C.java", "dead"), ("C.java", "Unused")])
end

@testitem ":unreferenced roots a PHP method, function, or class an attribute registers" setup = [Fixtures] tags = [:unreferenced] begin
    src = "<?php\n#[AsCommand('x')]\nclass Cmd {\n  #[Route('/x')]\n  private function handler() { }\n  #[\\Override]\n  private function dead() { }\n}\n"
    p = Fixtures.parsedfile(:php, src; file = "C.php")
    @test Fixtures.unref_sites([p]) == Set([("C.php", "dead")])
end

@testitem ":unreferenced roots a TypeScript or JavaScript class a decorator registers" setup = [Fixtures] tags = [:unreferenced] begin
    # An injector constructs a decorated class by registration, so nothing need name it.
    ts = Fixtures.parsedfile(:typescript, "@injectable()\nclass Service { }\nclass Dead { }\n"; file = "s.ts")
    @test Fixtures.unref_sites([ts]) == Set([("s.ts", "Dead")])
    js = Fixtures.parsedfile(:javascript, "@injectable()\nclass Service { }\nclass Dead { }\n"; file = "s.js")
    @test Fixtures.unref_sites([js]) == Set([("s.js", "Dead")])
end

@testitem ":unreferenced roots a Rust item an attribute registers" setup = [Fixtures] tags = [:unreferenced] begin
    # `#[test]` hands `checks` to the harness, through a further attribute, and `helper`
    # lives through it. `#[inline]` only annotates. An attribute on one item says nothing
    # about the next.
    src = "#[test]\n#[allow(unused)]\nfn checks() { helper(); }\nfn helper() {}\n#[inline]\nfn dead() {}\n#[test]\nfn other() {}\nfn after() {}\n"
    r = Fixtures.parsedfile(:rust, src; file = "m.rs")
    @test Fixtures.unref_sites([r]) == Set([("m.rs", "dead"), ("m.rs", "after")])
end

@testitem ":unreferenced roots a Ruby method its base class plausibly calls" setup = [Fixtures] tags = [:unreferenced] begin
    # `View#render` overrides `Base#render`, which `Base#run` calls. `View#dead` matches
    # nothing in `Base`. `Ext` extends a class outside the corpus, whose methods are
    # unknown, so any of its methods may be an override.
    src = "class Base\n  def run\n    render\n  end\n  def render\n  end\nend\nclass View < Base\n  private\n  def render\n    1\n  end\n  def dead\n  end\nend\nclass Ext < Outside::Thing\n  private\n  def hook\n  end\nend\n"
    r = Fixtures.parsedfile(:ruby, src; file = "v.rb")
    @test Fixtures.unref_sites([r]) == Set([("v.rb", "dead")])
end

@testitem ":unreferenced leaves a subclass method alone where it is no reachability node" setup = [Fixtures] tags = [:unreferenced] begin
    # A Python, C++, TypeScript, or JavaScript class body is no namespace, so its methods
    # are never judged, override or not. A Java or PHP private method cannot override, so
    # it is judged in a subclass as anywhere else.
    @test isempty(Fixtures.unref_sites([Fixtures.parsedfile(:python, "class V(Base):\n    def render(self):\n        pass\n"; file = "v.py")]))
    @test isempty(Fixtures.unref_sites([Fixtures.parsedfile(:cpp, "class V : public Base {\n  void render() { }\n};\nint main() { V v; return 0; }\n"; file = "v.cpp")]))
    @test isempty(Fixtures.unref_sites([Fixtures.parsedfile(:typescript, "export class V extends Base {\n  render(): void { }\n}\n"; file = "v.ts")]))
    @test isempty(Fixtures.unref_sites([Fixtures.parsedfile(:javascript, "export class V extends Base {\n  render() { }\n}\n"; file = "v.js")]))
    j = Fixtures.parsedfile(:java, "public class V extends Base {\n  private void render() { }\n}\n"; file = "V.java")
    @test Fixtures.unref_sites([j]) == Set([("V.java", "render")])
    p = Fixtures.parsedfile(:php, "<?php\nclass V extends Base {\n  private function render() { }\n}\n"; file = "V.php")
    @test Fixtures.unref_sites([p]) == Set([("V.php", "render")])
end

@testitem ":unreferenced reads a Python quoted annotation as a reference" setup = [Fixtures] tags = [:unreferenced] begin
    # A forward reference names its type in a string. Only a bare quoted name is read.
    src = "class _Node:\n    pass\nclass _Dead:\n    pass\ndef run(o: \"_Node\") -> None:\n    pass\n"
    p = Fixtures.parsedfile(:python, src; file = "m.py")
    @test Fixtures.unref_sites([p]) == Set([("m.py", "_Dead")])
end

@testitem ":unreferenced reads Rust pub as the public surface" setup = [Fixtures] tags = [:unreferenced] begin
    # `entry` is `pub`, a root, and calls `used`; `dead` is a private item nothing reaches.
    src = "pub fn entry() -> i32 { used() }\nfn used() -> i32 { 1 }\nfn dead() -> i32 { 2 }\n"
    r = Fixtures.parsedfile(:rust, src; file = "m.rs")
    @test Fixtures.unref_sites([r]) == Set([("m.rs", "dead")])
end

@testitem ":unreferenced reads a C static function as private" setup = [Fixtures] tags = [:unreferenced] begin
    # `entry` has external linkage, a root; `used` is static but reached through it; `dead`
    # is static, file-local, and unreferenced.
    src = "int entry() { return used(); }\nstatic int used() { return 1; }\nstatic int dead() { return 2; }\n"
    c = Fixtures.parsedfile(:c, src; file = "m.c")
    @test Fixtures.unref_sites([c]) == Set([("m.c", "dead")])
end

@testitem ":unreferenced reads a C++ static function as private" setup = [Fixtures] tags = [:unreferenced] begin
    src = "int entry() { return 1; }\nstatic int dead() { return 2; }\n"
    c = Fixtures.parsedfile(:cpp, src; file = "m.cpp")
    @test Fixtures.unref_sites([c]) == Set([("m.cpp", "dead")])
end

@testitem ":unreferenced reads a Ruby private method as private" setup = [Fixtures] tags = [:unreferenced] begin
    # `entry` precedes the `private` toggle, a root, and calls `used`; `dead` follows it
    # and nothing reaches it.
    src = "class C\n  def entry\n    used\n  end\n  private\n  def used\n    1\n  end\n  def dead\n    2\n  end\nend\n"
    r = Fixtures.parsedfile(:ruby, src; file = "m.rb")
    @test Fixtures.unref_sites([r]) == Set([("m.rb", "dead")])
end

@testitem ":unreferenced reads a Ruby protected method as private" setup = [Fixtures] tags = [:unreferenced] begin
    # `protected` marks `helper` and `dead` non-public, like `private`. `helper` is reached
    # through the call in `entry`, a within-file edge; `dead` is unreferenced.
    src = "class C\n  def entry\n    helper\n  end\n  protected\n  def helper\n    1\n  end\n  def dead\n    2\n  end\nend\n"
    r = Fixtures.parsedfile(:ruby, src; file = "m.rb")
    @test Fixtures.unref_sites([r]) == Set([("m.rb", "dead")])
end

@testitem ":unreferenced reads a Java private method as private" setup = [Fixtures] tags = [:unreferenced] begin
    # `e` is public, a root, and calls `used`; `dead` is a private method nothing reaches.
    # A private method is class-internal, so its uses are all same-file binding edges.
    src = "public class C {\n  public int e() { return used(); }\n  private int used() { return 1; }\n  private int dead() { return 2; }\n}\n"
    j = Fixtures.parsedfile(:java, src; file = "C.java")
    @test Fixtures.unref_sites([j]) == Set([("C.java", "dead")])
end

@testitem ":unreferenced reads a PHP private method as private" setup = [Fixtures] tags = [:unreferenced] begin
    src = "<?php\nclass C {\n  public function e() { return \$this->used(); }\n  private function used() { return 1; }\n  private function dead() { return 2; }\n}\n"
    p = Fixtures.parsedfile(:php, src; file = "C.php")
    @test Fixtures.unref_sites([p]) == Set([("C.php", "dead")])
end

@testitem ":unreferenced resolves a Java class across its package" setup = [Fixtures] tags = [:unreferenced] begin
    # `Main` is public, a root; it names `Helper`, a package-private class in a sibling file
    # of the same package. The `:package` linkage resolves the reference without an import,
    # so the used `Helper` is not flagged.
    main = Fixtures.parsedfile(:java, "package p;\npublic class Main { int run() { return new Helper().work(); } }\n"; file = "p/Main.java")
    helper = Fixtures.parsedfile(:java, "package p;\nclass Helper { public int work() { return 1; } }\n"; file = "p/Helper.java")
    @test isempty(Dendro.cluster_unreferenced([main, helper], Dendro.corpus_symbols([main, helper])))
end

@testitem ":unreferenced flags a dead package-private Java class" setup = [Fixtures] tags = [:unreferenced] begin
    # `Dead` is package-private and no file in the package names it, so it is unreachable.
    # `Main` is public, a root, and does not reference it.
    main = Fixtures.parsedfile(:java, "package p;\npublic class Main { int run() { return 1; } }\n"; file = "p/Main.java")
    dead = Fixtures.parsedfile(:java, "package p;\nclass Dead { public int work() { return 1; } }\n"; file = "p/Dead.java")
    @test Fixtures.unref_sites([main, dead]) == Set([("p/Dead.java", "Dead")])
end

@testitem ":unreferenced roots a module's __init__" setup = [Fixtures] tags = [:unreferenced] begin
    # Julia's runtime calls `__init__` when it loads a module, a package extension's
    # included, so nothing in the source names it. What it calls stays live through it.
    a = Fixtures.parsedfile(:julia, "module M\nfunction __init__()\n    setup()\nend\nsetup() = 1\nend\n"; file = "a.jl")
    ext = Fixtures.parsedfile(:julia, "module FooExt\n__init__() = nothing\nend\n"; file = "ext.jl")
    @test isempty(Fixtures.unref_sites([a]))
    @test isempty(Fixtures.unref_sites([ext]))

    # Only that exact name is the runtime's; a lookalike is an ordinary private function.
    b = Fixtures.parsedfile(:julia, "module M\ninit() = 1\nend\n"; file = "b.jl")
    @test Fixtures.unref_sites([b]) == Set([("b.jl", "init")])
end

@testitem ":unreferenced roots the entry points a config names" setup = [Fixtures] tags = [:unreferenced] begin
    # `connect` is called from outside the scanned roots, a loader script or another
    # package, so nothing in the corpus reaches it or what it calls.
    src = "module M\nconnect() = serve()\nserve() = helper()\nhelper() = 1\ndead() = 2\nend\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test Fixtures.unref_sites([a]) == Set([("a.jl", n) for n in ("connect", "serve", "helper", "dead")])

    # Naming it a root reaches it and everything it reaches; the rest is still dead.
    flagged = Dendro.cluster_unreferenced([a], Dendro.corpus_symbols([a]); roots = ["connect"])
    @test Set(first(f.locations).unit for f in flagged) == Set(["dead"])

    # `analyze` reads the names from `[unreferenced] roots`.
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), src)
        cfgfile = joinpath(dir, "c.toml")
        write(cfgfile, "[unreferenced]\nroots = [\"connect\"]\n")
        mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                cfg = Dendro.discover_config([dir]; explicit = cfgfile)
                dead = [first(f.locations).unit for f in Dendro.analyze(dir; config = cfg) if f.metric === :unreferenced]
                @test dead == ["dead"]
            end
        end
    end
end
