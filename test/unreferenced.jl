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

@testitem ":unreferenced reads a JS export list as the public surface" setup = [Fixtures] tags = [:unreferenced] begin
    src = "export function keep() { return used(); }\nfunction used() { return 1; }\nfunction dead() { return 2; }\n"
    j = Fixtures.parsedfile(:javascript, src; file = "m.js")
    @test Fixtures.unref_sites([j]) == Set([("m.js", "dead")])
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
