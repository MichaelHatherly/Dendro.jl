@testitem "pattern declarations parse into specs" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: discover_config

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(
            f, """
            [patterns.abstract_field]
            message = "field typed Any forces a boxed load"

            [patterns.empty_catch_binding]
            message  = "catch with no binding"
            severity = "high"

            [patterns.magic_number]
            message = "unnamed numeric literal"
            kind    = "scalar"
            band    = [3, 6]
            """
        )
        cfg = Fixtures.isolated_config(dir, f)
        specs = Dict(s.name => s for s in cfg.patterns)

        @test length(cfg.patterns) == 3
        # Sorted by name, so a report reads in a stable order.
        @test [s.name for s in cfg.patterns] == [:abstract_field, :empty_catch_binding, :magic_number]

        @test specs[:abstract_field].message == "field typed Any forces a boxed load"
        @test specs[:abstract_field].severity === :warn   # the default keeps a new rule out of the gate
        @test specs[:abstract_field].kind === :flag
        @test specs[:abstract_field].band === nothing

        @test specs[:empty_catch_binding].severity === :high
        @test specs[:magic_number].kind === :scalar
        @test specs[:magic_number].band == (3, 6)
    end
end

@testitem "pattern declarations reject malformed tables" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError

    bad = [
        # A missing message: the finding would have nothing to say.
        ("[patterns.a]\n", "message"),
        # A value the author clearly meant to set, so an error rather than a warning.
        ("[patterns.a]\nmessage = \"m\"\nseverity = \"critical\"\n", "severity"),
        ("[patterns.a]\nmessage = \"m\"\nkind = \"vector\"\n", "kind"),
        # A flag carries no band; a scalar cannot go without one.
        ("[patterns.a]\nmessage = \"m\"\nband = [1, 2]\n", "band"),
        ("[patterns.a]\nmessage = \"m\"\nkind = \"scalar\"\n", "band"),
        # ADR line 50: a band starting below 1 lets a unit with no matches score.
        ("[patterns.a]\nmessage = \"m\"\nkind = \"scalar\"\nband = [0, 2]\n", "1"),
        # `guard` says whether silence is wanted, so a non-boolean is not a guess to make.
        ("[patterns.a]\nmessage = \"m\"\nguard = \"yes\"\n", "guard"),
    ]
    for (toml, needle) in bad
        mktempdir() do dir
            f = joinpath(dir, "c.toml")
            write(f, toml)
            err = try
                Fixtures.isolated_config(dir, f)
                nothing
            catch e
                e
            end
            @test err isa ConfigError
            @test occursin(needle, err.msg)
        end
    end
end

@testitem "pattern declarations warn on an unknown key" setup = [Fixtures] tags = [:patterns] begin
    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(f, "[patterns.a]\nmessage = \"m\"\nnonsense = 1\n")
        cfg = @test_logs (:warn,) match_mode = :any Fixtures.isolated_config(dir, f)
        # Warned and dropped, as an unknown band does: the rule still loads.
        @test only(cfg.patterns).name === :a
    end
end

@testitem "pattern dirs cascade global then repo" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: pattern_dirs

    root, srcdir = Fixtures.gitrepo()
    repo_dir = joinpath(root, ".dendro", "patterns")
    mkpath(repo_dir)
    mktempdir() do xdg
        global_dir = joinpath(xdg, "dendro", "patterns")
        mkpath(global_dir)
        cfg = withenv("XDG_CONFIG_HOME" => xdg) do
            Dendro.discover_config([srcdir])
        end
        dirs = withenv("XDG_CONFIG_HOME" => xdg) do
            pattern_dirs(cfg, [srcdir])
        end
        # Global first, repo second: the later entry wins for a rule defined in both.
        # Resolved before comparing: macOS maps /var to /private/var and the repo dir
        # arrives through `git rev-parse`, which reports the real path.
        @test realpath.(dirs) == realpath.([global_dir, repo_dir])
    end
end

@testitem "patterns_dir resolves against its config file" setup = [Fixtures] tags = [:patterns] begin
    root, srcdir = Fixtures.gitrepo()
    elsewhere = joinpath(root, "lint", "queries")
    mkpath(elsewhere)
    write(joinpath(root, ".dendro.toml"), "patterns_dir = \"lint/queries\"\n")

    cfg = Fixtures.isolated_config([srcdir])
    # Relative to the config's own directory, never the process working directory,
    # so running dendro from a subdirectory keeps working.
    @test realpath(cfg.patterns_dir) == realpath(elsewhere)
    @test realpath.(Dendro.pattern_dirs(cfg, [srcdir])) == [realpath(elsewhere)]
end

@testitem "a malformed pattern query names its file and line" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: compile_pattern_query, ConfigError, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    cases = [
        # A node type the grammar does not have: caught by tree-sitter at compile.
        ("(call_expression) @a\n(no_such_node) @b\n", "node type", 2),
        # A capture a predicate references but no pattern binds.
        ("(identifier) @a\n\n((identifier) @b (#eq? @nope \"x\"))\n", "capture", 3),
        ("(call_expression @a\n", "syntax", 1),
    ]
    for (src, kind, line) in cases
        err = try
            compile_pattern_query(g, src, "julia.patterns.scm")
            nothing
        catch e
            e
        end
        @test err isa ConfigError
        @test occursin(kind, err.msg)
        @test occursin("line $line", err.msg)
    end
end

@testitem "an unimplemented predicate is rejected at load" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: compile_pattern_query, ConfigError, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    # A predicate tree-sitter has never heard of compiles cleanly and then rejects every
    # match, so a rule using it reports nothing and reads as clean code. That is the one
    # hole tree-sitter leaves. `#same-line?` stands in for any plausible-sounding name a
    # rule might reach for.
    src = "(identifier) @a\n((identifier) @b (#same-line? @b @a))\n"
    err = try
        compile_pattern_query(g, src, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("same-line?", err.msg)
    @test occursin("line 2", err.msg)
    @test occursin("any-of?", err.msg)   # names the alternatives

    # Every implemented predicate compiles, the tree predicates included.
    ok = "((identifier) @a (#any-of? @a \"x\" \"y\"))\n((identifier) @c (#match? @c \"^z\"))\n" *
        "((identifier) @d (#not-has-ancestor? @d \"function_definition\"))\n" *
        "((if_statement . (_) @_e (elseif_clause . (_) @_f)) @g (#structure-eq? @_e @_f))\n"
    @test compile_pattern_query(g, ok, "julia.patterns.scm") isa Dendro.TreeSitter.Query
end

@testitem "pattern negation excludes the more specific match" setup = [Fixtures] tags = [:patterns] begin
    # Three catch clauses: bare, bare with a trailing comment, and one binding `e`.
    # The comment parses as a sibling between `catch` and the block, which is what
    # breaks the tree-sitter anchor `(catch_clause . (block))`, which is why negation
    # subtracts by node identity instead.
    src = """
    try r() catch; h() end
    try r() catch # a note
        h() end
    try r() catch e; h(e) end
    """
    lines = Fixtures.pattern_lines(
        :julia, src, :empty_catch_binding, """
        (catch_clause) @empty_catch_binding
        (catch_clause (identifier)) @empty_catch_binding.not
        """
    )
    @test lines == [1, 2]
end

@testitem "a helper capture never becomes a rule" setup = [Fixtures] tags = [:patterns] begin
    src = """
    a() = print("x")
    b() = log("y")
    """
    # `@_n` exists only so `#eq?` has something to reference. Were it treated as a rule
    # it would fire on every identifier the predicate examined.
    query = """
    ((call_expression (identifier) @_n) @print_call (#eq? @_n "print"))
    """
    @test Fixtures.pattern_lines(:julia, src, :print_call, query) == [1]
    @test Fixtures.pattern_lines(:julia, src, :_n, query) == Int[]
    @test Dendro.is_helper_capture("_n")
    @test !Dendro.is_helper_capture("print_call")
end

@testitem "two patterns share one capture name" setup = [Fixtures] tags = [:patterns] begin
    src = """
    console.log("a");
    logger.log("b");
    debugger;
    """
    # One rule, two shapes: they accumulate into one bucket rather than the second
    # replacing the first.
    query = """
    ((call_expression function: (member_expression object: (identifier) @_o))
     @debug_output (#eq? @_o "console"))
    (debugger_statement) @debug_output
    """
    @test Fixtures.pattern_lines(:javascript, src, :debug_output, query) == [1, 3]
end

@testitem "a capture naming no declared rule is rejected" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError, PatternSpec, check_declared_rules, compile_pattern_query,
        language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    specs = [PatternSpec(:abstract_field, "m", :warn, :flag, nothing)]

    # A typo'd capture would otherwise report under a name nobody wrote.
    q = compile_pattern_query(g, "(identifier) @abstract_fieldy\n", "julia.patterns.scm")
    err = try
        check_declared_rules(q, specs, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("abstract_fieldy", err.msg)
    @test occursin("[patterns.abstract_fieldy]", err.msg)
    @test occursin("_", err.msg)   # points at the helper convention too

    # The declared rule, its `.not` companion, and a helper all pass.
    ok = compile_pattern_query(
        g, "(identifier) @abstract_field\n(identifier) @abstract_field.not\n((identifier) @_h (#eq? @_h \"x\"))\n",
        "julia.patterns.scm"
    )
    @test check_declared_rules(ok, specs, "julia.patterns.scm") === nothing
end

@testitem "declared captures are read off the query, not a walk" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: compile_pattern_query, declared_captures, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    # `no_such_shape` matches nothing anywhere, but is still declared: that is what lets
    # a repo rule shadow a user-global one even in a file where it does not fire.
    q = compile_pattern_query(g, "(identifier) @a\n(while_statement) @b\n", "p.scm")
    @test sort(declared_captures(q)) == ["a", "b"]
end

@testitem "the repo file shadows the global one per rule" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: PatternSpec, pattern_queries, index_all_patterns!, pattern_hits, PROFILES

    mktempdir() do dir
        global_dir = joinpath(dir, "global")
        repo_dir = joinpath(dir, "repo")
        mkpath(global_dir)
        mkpath(repo_dir)
        # Both define `shared`; only the global defines `only_global`.
        write(
            joinpath(global_dir, "julia.patterns.scm"),
            "(while_statement) @shared\n(for_statement) @only_global\n"
        )
        write(joinpath(repo_dir, "julia.patterns.scm"), "(if_statement) @shared\n")

        src = "function f(x)\n    while x\n    end\n    for i in x\n    end\n    if x\n    end\nend\n"
        specs = [
            PatternSpec(:shared, "m", :warn, :flag, nothing),
            PatternSpec(:only_global, "m", :warn, :flag, nothing),
        ]
        queries = pattern_queries(PROFILES[:julia], [global_dir, repo_dir], specs)
        index = Fixtures.idx(:julia, src)
        tree = Dendro.TreeSitter.parse(Dendro.parser_for(:julia), src)
        index_all_patterns!(index, tree, queries, src)

        line(name) = sort!([Int(Dendro.TreeSitter.start_point(n).row) + 1 for n in pattern_hits(index, name)])
        # The repo's `shared` wins outright: the global's `while` match is dropped.
        @test line(:shared) == [6]
        # A rule only the global defines still applies, so the locations compose.
        @test line(:only_global) == [4]
    end
end

@testitem "a repo rule shadows even where it matches nothing" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: PatternSpec, pattern_queries, index_all_patterns!, pattern_hits, PROFILES

    mktempdir() do dir
        global_dir = joinpath(dir, "global")
        repo_dir = joinpath(dir, "repo")
        mkpath(global_dir)
        mkpath(repo_dir)
        write(joinpath(global_dir, "julia.patterns.scm"), "(while_statement) @shared\n")
        # Declared but matches nothing in this file. Shadowing reads declared captures,
        # not matched ones, so the global must not leak back in here.
        write(joinpath(repo_dir, "julia.patterns.scm"), "(for_statement) @shared\n")

        src = "function f(x)\n    while x\n    end\nend\n"
        specs = [PatternSpec(:shared, "m", :warn, :flag, nothing)]
        index = Fixtures.idx(:julia, src)
        tree = Dendro.TreeSitter.parse(Dendro.parser_for(:julia), src)
        index_all_patterns!(index, tree, pattern_queries(PROFILES[:julia], [global_dir, repo_dir], specs), src)
        @test isempty(pattern_hits(index, :shared))
    end
end

@testitem "a warn pattern rule reports but does not gate" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze, errors

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "((struct_definition (block (typed_expression (identifier) (identifier) @_t) @abstract_field)) (#eq? @_t \"Any\"))\n"
    )
    write(joinpath(root, ".dendro.toml"), "[patterns.abstract_field]\nmessage = \"field typed Any forces a boxed load\"\n")
    write(joinpath(srcdir, "f.jl"), "struct S\n    a::Any\n    b::Int\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hit = only(filter(f -> f.metric === :abstract_field, analyze(srcdir)))
            @test hit.absolute === :warn
            @test hit.kind === :flag
            @test only(hit.locations).line == 2   # the field, not the struct
            # The load-bearing one: a warn rule cannot reach the gate floor, so declaring
            # a rule can never make `errors` unsatisfiable. Asserted on the rule rather
            # than on an empty gate, since the fixture trips `:unreferenced` too.
            @test isempty(filter(f -> f.metric === :abstract_field, errors(srcdir)))
        end
    end
end

@testitem "a high pattern rule reaches the gate" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: errors

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "(catch_clause) @empty_catch_binding\n(catch_clause (identifier)) @empty_catch_binding.not\n"
    )
    write(
        joinpath(root, ".dendro.toml"),
        "[patterns.empty_catch_binding]\nmessage = \"catch with no binding\"\nseverity = \"high\"\n"
    )
    write(joinpath(srcdir, "f.jl"), "function f(x)\n    try\n        g(x)\n    catch\n    end\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            errs = errors(srcdir)
            @test any(f -> f.metric === :empty_catch_binding && f.absolute === :high, errs)
        end
    end
end

@testitem "a pattern rule suppresses by name" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze, active

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "((struct_definition (block (typed_expression (identifier) (identifier) @_t) @abstract_field)) (#eq? @_t \"Any\"))\n"
    )
    write(joinpath(root, ".dendro.toml"), "[patterns.abstract_field]\nmessage = \"m\"\n")
    # The directive names the rule; validation reads the active rule set, which a
    # pattern rule joins, so no separate registration is needed.
    write(joinpath(srcdir, "f.jl"), "struct S\n    # dendro-ignore: abstract_field -- heterogeneous by design\n    a::Any\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            hits = filter(f -> f.metric === :abstract_field, analyze(srcdir))
            # Marked, not dropped: the count stays honest.
            @test only(hits).suppressed
            @test isempty(filter(f -> f.metric === :abstract_field, active(analyze(srcdir))))
        end
    end
end

@testitem "a pattern rule toggles off through [rules]" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "((struct_definition (block (typed_expression (identifier) (identifier) @_t) @abstract_field)) (#eq? @_t \"Any\"))\n"
    )
    write(
        joinpath(root, ".dendro.toml"),
        "[patterns.abstract_field]\nmessage = \"m\"\n\n[rules]\nabstract_field = false\n"
    )
    write(joinpath(srcdir, "f.jl"), "struct S\n    a::Any\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(filter(f -> f.metric === :abstract_field, analyze(srcdir)))
        end
    end
end

@testitem "a rule that matched nothing is reported" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    # `never_fires` is well-formed and names a real node type, so nothing at load catches
    # it. It just never occurs in this corpus, which is the case only a scan can see.
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "(while_statement) @loop_rule\n(macro_definition) @never_fires\n"
    )
    write(
        joinpath(root, ".dendro.toml"),
        "[patterns.loop_rule]\nmessage = \"m\"\n\n[patterns.never_fires]\nmessage = \"m\"\n"
    )
    write(joinpath(srcdir, "f.jl"), "function f(x)\n    while x\n        g()\n    end\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            found = analyze(srcdir)
            @test found.unmatched == [:never_fires]
            @test occursin("never_fires", sprint(show, MIME"text/plain"(), found))
        end
    end
end

@testitem "a guard rule matching nothing is not reported" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    # Both rules are silent on this corpus for the same reason. Only the declaration says
    # which silence was wanted.
    write(
        joinpath(root, ".dendro", "patterns", "julia.patterns.scm"),
        "(macro_definition) @never_fires\n(while_statement) @no_loops\n"
    )
    write(
        joinpath(root, ".dendro.toml"),
        """
        [patterns.never_fires]
        message = "m"

        [patterns.no_loops]
        message = "m"
        guard   = true
        """
    )
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            found = analyze(srcdir)
            @test found.unmatched == [:never_fires]
            @test !occursin("no_loops", sprint(show, MIME"text/plain"(), found))
        end
    end
end

@testitem "a guard rule still reports what it matches" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    # `guard` says silence is the wanted state, never that the rule is off. A project that
    # writes the shape anyway gets the finding.
    write(joinpath(root, ".dendro", "patterns", "julia.patterns.scm"), "(while_statement) @no_loops\n")
    write(
        joinpath(root, ".dendro.toml"),
        "[patterns.no_loops]\nmessage = \"m\"\nguard = true\n"
    )
    write(joinpath(srcdir, "f.jl"), "function f(x)\n    while x\n        g()\n    end\nend\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            found = analyze(srcdir)
            @test isempty(found.unmatched)
            @test any(f -> f.metric === :no_loops, found)
        end
    end
end

@testitem "a rule with no query for the corpus is not reported" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: analyze

    root, srcdir = Fixtures.gitrepo()
    mkpath(joinpath(root, ".dendro", "patterns"))
    # Declared, and realised only for Python. A Julia corpus gives it nothing to say,
    # which is not the same as the rule being broken.
    write(joinpath(root, ".dendro", "patterns", "python.patterns.scm"), "(pass_statement) @py_only\n")
    write(joinpath(root, ".dendro.toml"), "[patterns.py_only]\nmessage = \"m\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(analyze(srcdir).unmatched)
        end
    end
end

@testitem "a language queries path resolves against its config" setup = [Fixtures] tags = [:patterns] begin
    root, srcdir = Fixtures.gitrepo()
    qdir = joinpath(root, "vendor", "zig-queries")
    mkpath(qdir)
    write(joinpath(root, ".dendro.toml"), "[languages.zig]\ngrammar = \"python\"\nqueries = \"vendor/zig-queries\"\nextensions = [\"zig\"]\n")

    cfg = Fixtures.isolated_config([srcdir])
    # Relative to the declaring config, never the process working directory, so a scan
    # started from a subdirectory still finds the queries.
    @test realpath(cfg.languages[:zig].queries) == realpath(qdir)
end

@testitem "one rule name realised in two grammars" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: check_patterns

    root, srcdir = Fixtures.gitrepo()
    pdir = joinpath(root, ".dendro", "patterns")
    mkpath(joinpath(pdir, "tests"))

    # One declaration and two realisations, which is what keeps a rule's message
    # language-independent. Python holds the operator in `comparison_operator` as an
    # anonymous token, so one pattern covers both operand orders; Julia makes it a named
    # child, and sibling patterns match in source order, so each order needs its own.
    write(
        joinpath(pdir, "julia.patterns.scm"), """
        ((binary_expression (operator) @_op (identifier) @_n) @optional_equality
         (#eq? @_op "==") (#eq? @_n "nothing"))
        ((binary_expression (identifier) @_n (operator) @_op) @optional_equality
         (#eq? @_op "==") (#eq? @_n "nothing"))
        """
    )
    write(joinpath(pdir, "python.patterns.scm"), """((comparison_operator "==" (none)) @optional_equality)\n""")
    write(joinpath(root, ".dendro.toml"), "[patterns.optional_equality]\nmessage = \"identity is the question\"\n")
    write(joinpath(srcdir, "f.jl"), "f(x) = x\n")

    # Each fixture marks the rule and leaves the identity spelling unmarked, so a rule
    # realised in one grammar and not the other fails as a missed expectation.
    write(
        joinpath(pdir, "tests", "julia.jl"), """
        function f(x)
            if x == nothing    # dendro-expect: optional_equality
                return 0
            end
            if x === nothing
                return 1
            end
            return 2
        end
        """
    )
    write(
        joinpath(pdir, "tests", "python.py"), """
        def f(x):
            if x == None:    # dendro-expect: optional_equality
                return 0
            if x is None:
                return 1
            return 2
        """
    )

    mktempdir() do xdg
        withenv("XDG_CONFIG_HOME" => xdg) do
            @test isempty(check_patterns(srcdir))
        end
    end
end
