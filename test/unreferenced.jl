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

@testitem ":unreferenced never fires for a language with no public surface" setup = [Fixtures] tags = [:unreferenced] begin
    # Rust has no public-surface predicate yet, so every definition defaults to public:
    # no false positives until the per-def visibility modifier lands.
    src = "fn dead() -> i32 { 1 }\nfn other() -> i32 { 2 }\n"
    r = Fixtures.parsedfile(:rust, src; file = "m.rs")
    @test isempty(Dendro.cluster_unreferenced([r], Dendro.corpus_symbols([r])))
end
