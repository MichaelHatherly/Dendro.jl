@testitem "QueryIndex identifies functions and concepts (julia)" setup = [Fixtures] tags = [:query_index] begin
    src = "function f(x)\n    # TODO\n    if x > 0 && x < 9\n        g(x)\n    end\nend\ng(y) = y && y\n"
    i = Fixtures.idx(:julia, src)

    # Both definitions, in source order: the full form and the short form.
    units = Dendro.units(i)
    @test [Dendro.unit_name(u, i) for u in units] == ["f", "g"]

    # The short form is tagged as such; the full form is not.
    @test Dendro.unit_node(units[2]) in i.short_function
    @test !(Dendro.unit_node(units[1]) in i.short_function)

    # Concept membership: one `if` (a decision and a nesting construct), one comment,
    # and two `&&` operators across the two functions.
    @test length(i.decision.nodes) == 1
    @test length(i.nesting.nodes) == 1
    @test length(i.comment.nodes) == 1
    @test length(i.short_circuit.nodes) == 2
end

@testitem "QueryIndex short-circuit is text-filtered (python)" setup = [Fixtures] tags = [:query_index] begin
    using TreeSitter

    # Python's `and`/`or` are anonymous keyword tokens; the query tags exactly those.
    i = Fixtures.idx(:python, "def f(x):\n    return x and y or z\n")
    @test length(i.short_circuit.nodes) == 2
    @test Set(strip(TreeSitter.slice(i.source, n)) for n in i.short_circuit.nodes) == Set(["and", "or"])
end

@testitem "@doc tags each language's documentation form" setup = [Fixtures] tags = [:query_index] begin
    using TreeSitter

    # One documented definition per language, written the way that language's readers and
    # doc tools expect. What the query has to get right is which node carries the
    # documentation; `:undocumented_public` reads adjacency from there.
    cases = [
        (:julia, "\"\"\"\nDocs.\n\"\"\"\nf() = 1\n"),
        (:python, "def f():\n    \"\"\"Docs.\"\"\"\n    return 1\n"),
        (:rust, "/// Docs.\npub fn f() {}\n"),
        (:java, "class C {\n    /** Docs. */\n    int f() { return 1; }\n}\n"),
        (:javascript, "/** Docs. */\nfunction f() { return 1; }\n"),
        (:typescript, "/** Docs. */\nfunction f(): number { return 1; }\n"),
        (:c, "/** Docs. */\nint f(void) { return 1; }\n"),
        (:cpp, "/** Docs. */\nint f() { return 1; }\n"),
        (:php, "<?php\n/** Docs. */\nfunction f() { return 1; }\n"),
        (:go, "package p\n\n// Docs.\nfunc F() int { return 1 }\n"),
        (:ruby, "# Docs.\ndef f\n  1\nend\n"),
    ]
    @testset "$lang" for (lang, src) in cases
        i = Fixtures.idx(lang, src)
        @test length(i.doc.nodes) == 1
        @test occursin("Docs.", TreeSitter.slice(i.source, only(i.doc.nodes)))
    end
end

@testitem "@doc leaves a comment that documents something else" setup = [Fixtures] tags = [:query_index] begin
    # Rust's `//!` documents the module around it and a plain comment documents nothing,
    # so neither is a definition's documentation. Python's docstring is the first string
    # in the body, so a comment above the `def` is not one. Java's `/* */` is not javadoc.
    @test isempty(Fixtures.idx(:rust, "//! Module docs.\n/* Aside. */\npub fn f() {}\n").doc.nodes)
    @test isempty(Fixtures.idx(:python, "# Aside.\ndef f():\n    return 1\n").doc.nodes)
    @test isempty(Fixtures.idx(:java, "class C {\n    /* Aside. */\n    int f() { return 1; }\n}\n").doc.nodes)
end

@testitem "@doc is silent for a language with no documentation form (bash)" setup = [Fixtures] tags = [:query_index] begin
    # Bash has no documentation convention a parser can read, so the query tags nothing
    # and the rule says nothing about a bash corpus.
    @test isempty(Fixtures.idx(:bash, "# Aside.\nf() {\n  echo hi\n}\n").doc.nodes)
end

@testitem "@attribute tags the rust items a doc comment sits above" setup = [Fixtures] tags = [:query_index] begin
    # Rust writes `#[...]` as a sibling above the item, so a doc comment above an
    # attribute is not on the line before the definition. Every other language Dendro
    # reads puts its attributes inside the declaration node, and tags none here.
    i = Fixtures.idx(:rust, "/// Docs.\n#[inline]\npub fn f() {}\n")
    @test length(i.attribute.nodes) == 1
    @test isempty(Fixtures.idx(:php, "<?php\n#[Attr]\nfunction f() {}\n").attribute.nodes)
    @test isempty(Fixtures.idx(:java, "class C {\n    @Override\n    int f() { return 1; }\n}\n").attribute.nodes)
end

@testitem "@inherits_doc tags the definition an override marker covers" setup = [Fixtures] tags = [:query_index] begin
    using TreeSitter

    # The capture is the node holding the overriding definition, so the definition sits
    # inside it: the marked method in Java, TypeScript, C++ and PHP, the decorated
    # definition in Python, and the whole trait impl in Rust, where rustdoc shows the
    # trait's docs on every method of it. A plain method, decorator, or inherent impl
    # carries no such node.
    cases = [
        (:java, "class C {\n    @Override\n    int f() { return 1; }\n    @Deprecated\n    int g() { return 1; }\n}\n"),
        (:typescript, "class C extends B {\n    override f(): number { return 1; }\n    g(): number { return 1; }\n}\n"),
        (:cpp, "struct C : B {\n    int f() override { return 1; }\n    int g() { return 1; }\n};\n"),
        (:php, "<?php\nclass C extends B {\n    #[\\Override]\n    function f() { return 1; }\n    #[Pure]\n    function g() { return 1; }\n}\n"),
        (:python, "class C(B):\n    @override\n    def f(self):\n        return 1\n    @cached\n    def g(self):\n        return 1\n"),
        (:rust, "impl Trait for T {\n    fn f(&self) {}\n}\nimpl T {\n    fn g(&self) {}\n}\n"),
    ]
    @testset "$lang" for (lang, src) in cases
        i = Fixtures.idx(lang, src)
        @test length(i.inherits_doc.nodes) == 1
        text = TreeSitter.slice(i.source, only(i.inherits_doc.nodes))
        @test occursin("f(", text)
        @test !occursin("g(", text)
    end
end

@testitem "@prototype tags a function declaration and never a definition" setup = [Fixtures] tags = [:query_index] begin
    # The capture is the declaration node, named through its declarator the way a
    # definition is, so a pointer return wrapping the declarator does not hide the name. A
    # definition and a variable initialised by a call are not prototypes.
    cases = [
        (:c, "int f(void);\nchar *g(int x);\nint h(void) { return 1; }\nint x = f();\n"),
        (:cpp, "int f();\nchar *g(int x);\nint h() { return 1; }\nint x = f();\n"),
    ]
    @testset "$lang" for (lang, src) in cases
        i = Fixtures.idx(lang, src)
        @test [Dendro.unit_name(n, i) for n in i.prototype.nodes] == ["f", "g"]
        @test [Dendro.line_of(n) for n in i.prototype.nodes] == [1, 2]
    end
    @test isempty(Fixtures.idx(:go, "package p\n\nfunc F() int { return 1 }\n").prototype.nodes)
end

@testitem "@nodoc tags an RDoc :nodoc: marker" setup = [Fixtures] tags = [:query_index] begin
    # The marker is a comment carrying `:nodoc:`, on a class line or a definition's. A plain
    # comment is not one, and no other language has the marker.
    i = Fixtures.idx(:ruby, "class C # :nodoc: all\n  # Docs.\n  def f # :nodoc:\n    1\n  end\nend\n")
    @test [Dendro.line_of(n) for n in i.nodoc.nodes] == [1, 3]
    @test isempty(Fixtures.idx(:python, "# :nodoc:\ndef f():\n    return 1\n").nodoc.nodes)
end

@testitem "@switch_arm tags the arms @decision counts (c)" setup = [Fixtures] tags = [:query_index] begin
    # `cyclomatic_modified` reads a switch as one decision by subtracting its arms from the
    # branch points, so an arm tagged for one concept and not the other leaves the
    # arithmetic short. C spells every arm, `default:` included, as one `case_statement`.
    i = Fixtures.idx(:c, "int f(int x){ switch(x){ case 1: a(); break; case 2: b(); break; default: c(); } return 0; }")
    @test length(i.switch_arm.nodes) == 3
    @test all(n in i.decision for n in i.switch_arm.nodes)
    @test length(i.switch_stmt.nodes) == 1
end

@testitem "a switch statement is never a branch point" tags = [:query_index] begin
    using TreeSitter

    # `modified_step` adds one for a switch statement and subtracts its arms, so a node
    # tagged as both a switch statement and a branch point would count twice and once
    # again as its own arm. Nothing in the metric code notices, so the queries carry the
    # invariant and this reads it off them: the node types one capture names, taken from
    # the compiled query's own pattern boundaries. Comments are blanked rather than cut so
    # those byte offsets still land, and the captures read here are flat lists of node
    # types and anonymous tokens, so the parenthesised and quoted names are all they say.
    function types_by_capture(lang)
        profile = Dendro.PROFILES[lang]
        src = read(joinpath(Dendro.queries_dir(profile), "$(lang).scm"), String)
        src = replace(src, r"(?m);[^\n]*" => m -> " "^length(m))
        query = Dendro.query_for(profile)
        bounds = [TreeSitter.start_byte_for_pattern(query, i) for i in 1:TreeSitter.pattern_count(query)]
        push!(bounds, lastindex(src) + 1)
        out = Dict{String, Set{String}}()
        for k in 1:(length(bounds) - 1)
            text = src[bounds[k]:(bounds[k + 1] - 1)]
            types = Set{String}()
            for m in eachmatch(r"\(\s*([a-z_][a-z_0-9]*)\s*\)", text)
                push!(types, m.captures[1])
            end
            for m in eachmatch(r"\"([^\"]*)\"", text)
                push!(types, m.captures[1])
            end
            for m in eachmatch(r"@([A-Za-z_][A-Za-z_0-9.]*)", text)
                union!(get!(out, m.captures[1], Set{String}()), types)
            end
        end
        return out
    end

    @testset "$lang" for lang in sort!(collect(keys(Dendro.PROFILES)))
        types = types_by_capture(lang)
        named(c) = get(types, c, Set{String}())
        branch_points = union(named("decision"), named("short_circuit"))
        @test isempty(intersect(named("switch_stmt"), branch_points))
        @test isempty(intersect(named("switch_stmt"), named("switch_arm")))
    end
end

@testitem "every capture name reaches its own QueryIndex field" tags = [:query_index] begin
    using Dendro: CONCEPT_NAMES, QueryIndex

    # Four capture names are Julia reserved words, so their fields are spelled out. The
    # mapping lives nowhere but the constructor's two parallel literals, the field list
    # and the `by_name` dictionary, which is what this table writes down.
    reserved = Dict(
        :catch => :catch_clause, :return => :return_stmt,
        :finally => :finally_clause, :try => :try_stmt,
    )
    field_for(name) = get(reserved, name, name)

    # A concept is added by editing both literals, and two branches each adding one merge
    # into code that compiles while filing one concept's captures under another's name.
    # `Concept()` allocates its own containers, so identity separates two empty concepts.
    idx = QueryIndex(:julia, "")
    @test Set(keys(idx.by_name)) == Set(string.(CONCEPT_NAMES))
    @testset "$name" for name in CONCEPT_NAMES
        @test idx.by_name[string(name)] === getfield(idx, field_for(name))
    end
end

@testitem "every query uses only known capture names" tags = [:query_index] begin
    using TreeSitter

    # Capture names declared by a compiled query, enumerated through the C API by id.
    function capture_names(q::TreeSitter.Query)
        return [
            unsafe_string(TreeSitter.API.ts_query_capture_name_for_id(q.ptr, UInt32(i), Ref{UInt32}()))
                for i in 0:(TreeSitter.capture_count(q) - 1)
        ]
    end

    # A capture outside CONCEPT_NAMES (or @function) has no field in QueryIndex and
    # would throw in dispatch!. Catch a typo'd capture here, including one that never
    # matches a node, before it reaches a parse. A `_`-prefixed capture anchors a
    # predicate and names no concept, so it is exempt in the query as it is in the index.
    valid = Set{String}(string.(Dendro.CONCEPT_NAMES))
    push!(valid, "function")
    @testset "$lang" for lang in sort!(collect(keys(Dendro.PROFILES)))
        named = filter(n -> !startswith(n, "_"), capture_names(Dendro.query_for(lang)))
        @test setdiff(Set(named), valid) == Set{String}()
    end
end

@testitem "every scopes query uses only known capture names" tags = [:query_index] begin
    using TreeSitter

    function capture_names(q::TreeSitter.Query)
        return [
            unsafe_string(TreeSitter.API.ts_query_capture_name_for_id(q.ptr, UInt32(i), Ref{UInt32}()))
                for i in 0:(TreeSitter.capture_count(q) - 1)
        ]
    end

    # A scopes query routes captures by name: `scope`, `reference`, or `definition.*`.
    # Any other capture mis-routes silently in the resolver. Catch a typo here, for
    # every language that ships a scopes query.
    fixed = Set{String}(["scope", "reference"])
    @testset "$lang" for lang in sort!(collect(keys(Dendro.PROFILES)))
        q = Dendro.scopes_query_for(lang)
        q === nothing && continue
        extra = filter(n -> !(n in fixed) && !startswith(n, "definition."), capture_names(q))
        @test isempty(extra)
    end
end

@testitem "every imports query uses only known capture names" tags = [:query_index] begin
    using TreeSitter

    function capture_names(q::TreeSitter.Query)
        return [
            unsafe_string(TreeSitter.API.ts_query_capture_name_for_id(q.ptr, UInt32(i), Ref{UInt32}()))
                for i in 0:(TreeSitter.capture_count(q) - 1)
        ]
    end

    # An imports query routes captures by name: `module`/`module.name` mark a namespace,
    # `import`/`import.*` an import, `export` a visibility marker, `include.path` a splice
    # target. Underscore captures are predicate helpers, never read. Any other capture is
    # a typo that mis-routes silently. Catch it, for every language that ships one.
    fixed = Set{String}(["module", "module.name", "export", "import", "include.path"])
    @testset "$lang" for lang in sort!(collect(keys(Dendro.PROFILES)))
        q = Dendro.imports_query_for(lang)
        q === nothing && continue
        extra = filter(capture_names(q)) do n
            !(n in fixed) && !startswith(n, "import.") && !startswith(n, "_")
        end
        @test isempty(extra)
    end
end
