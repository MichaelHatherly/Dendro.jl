# Documentation as adjacency. Each case builds a tiny corpus and checks which declared-
# public definitions the pass reports as undocumented. What a doc node says is never read,
# so every case turns on where the documentation sits rather than what it contains.
# `Fixtures.undocumented_names` returns the flagged names.

@testitem ":undocumented_public flags an exported definition with no docstring" setup = [Fixtures] tags = [:undocumented_public] begin
    src = "export documented, bare\n\"\"\"\nDocs.\n\"\"\"\ndocumented() = 1\n\nbare() = 2\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    f = only(Fixtures.undocumented([a]))
    @test f.metric == :undocumented_public
    @test f.absolute == :warn
    @test f.kind == :flag
    @test f.value === nothing
    @test first(f.locations).file == "a.jl"
    @test first(f.locations).line == 7
    @test first(f.locations).unit == "bare"
end

@testitem ":undocumented_public wants the docstring against the definition" setup = [Fixtures] tags = [:undocumented_public] begin
    # A blank line between the two is what separates a docstring from a string that
    # happens to sit earlier in the file, and Julia's own doc system reads it the same way.
    src = "export bare\n\"\"\"\nDocs.\n\"\"\"\n\nbare() = 1\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public says nothing about a private definition" setup = [Fixtures] tags = [:undocumented_public] begin
    # The question is whether a caller outside the corpus can find out what a name does.
    # A definition no caller outside can reach owes them nothing.
    src = "export keep\n\"\"\"\nDocs.\n\"\"\"\nkeep() = 1\nhidden() = 2\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test isempty(Fixtures.undocumented([a]))
end

@testitem ":undocumented_public asks nothing of a constant" setup = [Fixtures] tags = [:undocumented_public] begin
    # A language documents a table of constants once at the table, so asking after each entry
    # reports one observation dozens of times. The struct beside it is still asked after.
    src = "export LIMIT, Holder\nconst LIMIT = 3\nstruct Holder end\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test Fixtures.undocumented_names([a]) == Set(["Holder"])
end

@testitem ":undocumented_public reads a python docstring, not a comment above" setup = [Fixtures] tags = [:undocumented_public] begin
    src = """
    def documented():
        \"\"\"Docs.\"\"\"
        return 1

    # Not a docstring.
    def commented():
        return 2
    """
    a = Fixtures.parsedfile(:python, src; file = "a.py")
    @test Fixtures.undocumented_names([a]) == Set(["commented"])
end

@testitem ":undocumented_public gives a docstring to the definition holding it" setup = [Fixtures] tags = [:undocumented_public] begin
    # A method's docstring documents the method. Reading it as the class's would let one
    # documented member answer for the container, which is the reading a class with no
    # docstring of its own is meant to be flagged for.
    src = """
    class Bare:
        def m(self):
            \"\"\"Method docs.\"\"\"
            return 1
    """
    a = Fixtures.parsedfile(:python, src; file = "a.py")
    @test Fixtures.undocumented_names([a]) == Set(["Bare"])
end

@testitem ":undocumented_public steps over a rust attribute" setup = [Fixtures] tags = [:undocumented_public] begin
    # `#[inline]` sits between the doc comment and the item as a sibling of both, so the
    # documentation is two lines above what it documents.
    src = "/// Docs.\n#[inline]\npub fn documented() -> i32 { 1 }\n\npub fn bare() -> i32 { 2 }\n\nfn hidden() -> i32 { 3 }\n"
    a = Fixtures.parsedfile(:rust, src; file = "a.rs")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public leaves rust module documentation to the module" setup = [Fixtures] tags = [:undocumented_public] begin
    # `//!` documents the module around it, so it says nothing about the item below it.
    src = "//! Module docs.\npub fn bare() -> i32 { 1 }\n"
    a = Fixtures.parsedfile(:rust, src; file = "a.rs")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public reads each language's documentation form" setup = [Fixtures] tags = [:undocumented_public] begin
    # One documented public definition and one bare one per language, written the way that
    # language documents. Only the bare one is reported, so each case pins both readings.
    # The C and C++ files are headers, since a definition no header declares is not API.
    cases = [
        (:go, "a.go", "Bare", "package p\n\n// Documented does a thing.\n// More.\nfunc Documented() int { return 1 }\n\nfunc Bare() int { return 2 }\n\nfunc hidden() int { return 3 }\n"),
        (:java, "a.java", "bare", "/** Class docs. */\npublic class C {\n    /** Docs. */\n    @Override\n    public int documented() { return 1; }\n\n    public int bare() { return 2; }\n\n    private int hidden() { return 3; }\n}\n"),
        (:javascript, "a.js", "bare", "/** Docs. */\nexport function documented() { return 1; }\n\nexport function bare() { return 2; }\n\nfunction hidden() { return 3; }\n"),
        (:typescript, "a.ts", "bare", "/** Docs. */\nexport function documented(): number { return 1; }\n\nexport function bare(): number { return 2; }\n\nfunction hidden(): number { return 3; }\n"),
        (:php, "a.php", "bare", "<?php\n/** Docs. */\nfunction documented() { return 1; }\n\nfunction bare() { return 2; }\n"),
        (:ruby, "a.rb", "bare", "# Docs.\ndef documented\n  1\nend\n\ndef bare\n  2\nend\n"),
        (:c, "a.h", "bare", "/* Docs. */\nint documented(void) { return 1; }\n\nint bare(void) { return 2; }\n\nstatic int hidden(void) { return 3; }\n"),
        (:cpp, "a.hpp", "bare", "/* Docs. */\nint documented() { return 1; }\n\nint bare() { return 2; }\n\nstatic int hidden() { return 3; }\n"),
    ]
    @testset "$lang" for (lang, file, bare, src) in cases
        a = Fixtures.parsedfile(lang, src; file = file)
        @test Fixtures.undocumented_names([a]) == Set([bare])
    end
end

@testitem ":undocumented_public reads a plain C comment block as documentation" setup = [Fixtures] tags = [:undocumented_public] begin
    # curl and redis document with a plain `/* */` block above the definition, and C has no
    # docstring, so no other convention is left to prefer. The header declares the name
    # bare, so the block above the definition is the only documentation in the corpus.
    h = Fixtures.parsedfile(:c, "int documented(void);\n"; file = "a.h")
    c = Fixtures.parsedfile(:c, "/* Docs. */\nint documented(void) { return 1; }\n"; file = "a.c")
    @test isempty(Fixtures.undocumented([h, c]))
end

@testitem ":undocumented_public reads a documented prototype as documenting its definition" setup = [Fixtures] tags = [:undocumented_public] begin
    # curl documents at the prototype in the header, so the definition in the `.c` file
    # carries nothing above it and is documented all the same.
    h = Fixtures.parsedfile(:c, "/* Docs. */\nint documented(void);\n"; file = "a.h")
    c = Fixtures.parsedfile(:c, "int documented(void) { return 1; }\n"; file = "a.c")
    @test isempty(Fixtures.undocumented([h, c]))
end

@testitem ":undocumented_public leaves a C function no header declares alone" setup = [Fixtures] tags = [:undocumented_public] begin
    # A non-static function no header declares is file-local in practice whatever its
    # linkage: nothing outside the file can name it, so nobody outside has it to read about.
    c = Fixtures.parsedfile(:c, "int local(void) { return 1; }\n"; file = "a.c")
    @test isempty(Fixtures.undocumented([c]))
end

@testitem ":undocumented_public reports a header-declared C function once, at its definition" setup = [Fixtures] tags = [:undocumented_public] begin
    # The header makes the name API and documents it nowhere, so the definition is the one
    # finding. The prototype is a declaration and never a definition, so it is not a second.
    sites(files) = [(loc.file, loc.line, loc.unit) for f in Fixtures.undocumented(files) for loc in f.locations]
    h = Fixtures.parsedfile(:c, "int bare(void);\n"; file = "a.h")
    c = Fixtures.parsedfile(:c, "int bare(void) { return 1; }\n"; file = "a.c")
    @test sites([h, c]) == [("a.c", 1, "bare")]
end

@testitem ":undocumented_public shares a docstring across the methods of one Julia function" setup = [Fixtures] tags = [:undocumented_public] begin
    # One docstring documents a function, and the other methods of the same name in the
    # file read under it. A different name beside them is still asked after.
    src = "export f, g\n\"\"\"\nDocs.\n\"\"\"\nf(x) = 1\nf(x, y) = 2\ng() = 3\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test Fixtures.undocumented_names([a]) == Set(["g"])
end

@testitem ":undocumented_public asks after each Java overload on its own" setup = [Fixtures] tags = [:undocumented_public] begin
    # javadoc is per overload, so a documented `f()` says nothing about a bare `f(int)`.
    src = "/** Class docs. */\npublic class C {\n    /** Docs. */\n    public int f() { return 1; }\n\n    public int f(int x) { return 2; }\n}\n"
    j = Fixtures.parsedfile(:java, src; file = "C.java")
    @test Fixtures.undocumented_names([j]) == Set(["f"])
end

@testitem ":undocumented_public leaves an RDoc :nodoc: definition alone" setup = [Fixtures] tags = [:undocumented_public] begin
    # `:nodoc:` on the definition's line is the author declaring the name out of the
    # documented surface, and `:nodoc: all` on a class line covers its members too.
    @test isempty(Fixtures.undocumented([Fixtures.parsedfile(:ruby, "def foo # :nodoc:\n  1\nend\n"; file = "a.rb")]))
    src = "class C # :nodoc: all\n  def bare\n    1\n  end\nend\n"
    @test isempty(Fixtures.undocumented([Fixtures.parsedfile(:ruby, src; file = "a.rb")]))
end

@testitem ":undocumented_public leaves a Java package-private method alone" setup = [Fixtures] tags = [:undocumented_public] begin
    # `open` is reachable from its package and no further, so no caller outside the corpus
    # has it to read about. Only `api` is part of the surface the rule asks after.
    src = "/** Class docs. */\npublic class C {\n    public int api() { return 1; }\n\n    int open() { return 2; }\n\n    private int hidden() { return 3; }\n}\n"
    j = Fixtures.parsedfile(:java, src; file = "C.java")
    @test Fixtures.undocumented_names([j]) == Set(["api"])
end

@testitem ":undocumented_public leaves a Rust pub(crate) item alone" setup = [Fixtures] tags = [:undocumented_public] begin
    src = "pub fn api() -> i32 { 1 }\n\npub(crate) fn open() -> i32 { 2 }\n"
    r = Fixtures.parsedfile(:rust, src; file = "m.rs")
    @test Fixtures.undocumented_names([r]) == Set(["api"])
end

@testitem ":undocumented_public reads a constructor as documented by its class" setup = [Fixtures] tags = [:undocumented_public] begin
    # A class's documentation covers how to construct it, and RDoc, Sphinx and javadoc
    # present a bare constructor under the class's own docs. So a documented class with a
    # bare constructor reports nothing, and an undocumented one reports the class alone.
    sites(files) = Set((loc.line, loc.unit) for f in Fixtures.undocumented(files) for loc in f.locations)
    cases = [
        (:ruby, "a.rb", "# Docs.\nclass C\n  def initialize\n    @x = 1\n  end\nend\n", "class C\n  def initialize\n    @x = 1\n  end\nend\n", (1, "C")),
        (:python, "a.py", "class C:\n    \"\"\"Docs.\"\"\"\n\n    def __init__(self):\n        self.x = 1\n", "class C:\n    def __init__(self):\n        self.x = 1\n", (1, "C")),
        (:java, "C.java", "/** Docs. */\npublic class C {\n    public C() { }\n}\n", "public class C {\n    public C() { }\n}\n", (1, "C")),
    ]
    @testset "$lang" for (lang, file, documented, bare, site) in cases
        @test isempty(Fixtures.undocumented([Fixtures.parsedfile(lang, documented; file = file)]))
        @test sites([Fixtures.parsedfile(lang, bare; file = file)]) == Set([site])
    end
end

@testitem ":undocumented_public reads an overriding method as documented by what it overrides" setup = [Fixtures] tags = [:undocumented_public] begin
    # javadoc copies the overridden method's documentation onto an `@Override` method
    # with none of its own, so readers see it documented and the rule reads it the same
    # way. The class around it is still asked after.
    documented = "/** Docs. */\npublic class C extends B {\n    @Override\n    public int f() { return 1; }\n}\n"
    @test isempty(Fixtures.undocumented([Fixtures.parsedfile(:java, documented; file = "C.java")]))
    bare = "public class C extends B {\n    @Override\n    public int f() { return 1; }\n}\n"
    @test Fixtures.undocumented_names([Fixtures.parsedfile(:java, bare; file = "C.java")]) == Set(["C"])
end

@testitem ":undocumented_public reads a PHP override attribute" setup = [Fixtures] tags = [:undocumented_public] begin
    # One overriding method and one plain one under a documented class; only the plain one
    # is reported. PHP is the one language beside Java whose class body is a namespace in
    # its imports query, so the only other one whose methods reach the symbol table.
    src = "<?php\n/** Docs. */\nclass C extends B {\n    #[\\Override]\n    public function f() { return 1; }\n\n    public function bare() { return 2; }\n}\n"
    a = Fixtures.parsedfile(:php, src; file = "a.php")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public steps over a plain comment under a doc comment" setup = [Fixtures] tags = [:undocumented_public] begin
    # rustdoc, javadoc and tsc all attach a doc comment to the declaration below it across
    # an ordinary comment, so the test steps over comment lines the way it steps over
    # attributes. A blank line still breaks the run.
    src = "/// Docs.\n// An aside.\n// Another.\npub fn documented() -> i32 { 1 }\n\n/// Docs.\n\n// An aside.\npub fn bare() -> i32 { 2 }\n"
    a = Fixtures.parsedfile(:rust, src; file = "a.rs")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public keeps a docstring against its definition across a comment" setup = [Fixtures] tags = [:undocumented_public] begin
    # Julia's parser pairs a docstring with the expression directly below it and a comment
    # line between the two leaves the string unpaired, so only a doc comment reaches across
    # a comment.
    src = "export bare\n\"\"\"\nDocs.\n\"\"\"\n# An aside.\nbare() = 1\n"
    a = Fixtures.parsedfile(:julia, src; file = "a.jl")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public does not read a comment inside a body as documentation" setup = [Fixtures] tags = [:undocumented_public] begin
    # Go and Ruby take every comment as documentation, so a comment in the middle of a body
    # is a doc node sitting inside the definition. Only a docstring documents from inside;
    # a comment documents what follows it.
    a = Fixtures.parsedfile(:ruby, "def bare\n  # An aside.\n  1\nend\n"; file = "a.rb")
    @test Fixtures.undocumented_names([a]) == Set(["bare"])
end

@testitem ":undocumented_public says nothing about bash, which has no doc form" setup = [Fixtures] tags = [:undocumented_public] begin
    # No reader or doc tool agrees on what documents a bash function, so a bash corpus is
    # not one this rule has an opinion about. Silence, not a finding on every function.
    a = Fixtures.parsedfile(:bash, "f() {\n  echo hi\n}\n"; file = "a.sh")
    @test isempty(Fixtures.undocumented([a]))
end

@testitem ":undocumented_public is accepted by a dendro-ignore directive" setup = [Fixtures] tags = [:undocumented_public] begin
    src = "export bare\nbare() = 1 # dendro-ignore: undocumented_public\n"
    files = [
        Fixtures.parsedfile(
            :julia, src; file = "a.jl",
            directives = Dendro.suppressions(Fixtures.idx(:julia, src); file = "a.jl")
        ),
    ]

    # Accepted, not hidden: the finding stays in the vector carrying its mark.
    @test only(Fixtures.undocumented(files)).suppressed
end

@testitem "the documentation pass is off until a config turns it on" tags = [:undocumented_public] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        write(dir * "/a.jl", "export bare\nbare() = 1\n")
        undocumented(fs) = filter(f -> f.metric === :undocumented_public, fs)
        toml = joinpath(dir, "c.toml")

        # Whether a project documents its public surface is a project's own standard, so a
        # scan says nothing about it unasked.
        @test isempty(undocumented(analyze(dir)))

        write(toml, "[rules]\nundocumented_public = true\n")
        cfg = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir]; explicit = toml)
            end
        end
        found = only(undocumented(analyze(dir; config = cfg)))
        @test first(found.locations).unit == "bare"

        # A warning, never an error: the rule reports a standard a project opts into, and
        # `errors` is the floor a downstream package gates its own tests on.
        @test found.absolute === :warn
    end
end
