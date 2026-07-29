@testitem "pattern declarations parse into specs" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: discover_config

    mktempdir() do dir
        f = joinpath(dir, "c.toml")
        write(
            f, """
            [patterns.no_any]
            message = "`::Any` defeats dispatch"

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
        @test [s.name for s in cfg.patterns] == [:empty_catch_binding, :magic_number, :no_any]

        @test specs[:no_any].message == "`::Any` defeats dispatch"
        @test specs[:no_any].severity === :warn   # the default keeps a new rule out of the gate
        @test specs[:no_any].kind === :flag
        @test specs[:no_any].band === nothing

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
    # `#not-any-of?` compiles cleanly and then rejects every match, so a rule using it
    # reports nothing and reads as clean code. That is the one hole tree-sitter leaves.
    src = "(identifier) @a\n((identifier) @b (#not-any-of? @b \"x\"))\n"
    err = try
        compile_pattern_query(g, src, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("not-any-of?", err.msg)
    @test occursin("line 2", err.msg)
    @test occursin("any-of?", err.msg)   # names the alternatives

    # Every implemented predicate compiles.
    ok = "((identifier) @a (#any-of? @a \"x\" \"y\"))\n((identifier) @c (#match? @c \"^z\"))\n"
    @test compile_pattern_query(g, ok, "julia.patterns.scm") isa Dendro.TreeSitter.Query
end

@testitem "pattern negation excludes the more specific match" setup = [Fixtures] tags = [:patterns] begin
    # Three catch clauses: bare, bare with a trailing comment, and one binding `e`.
    # The comment parses as a sibling between `catch` and the block, which is what
    # breaks the tree-sitter anchor `(catch_clause . (block))` that ADR-0001 proposed.
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
    specs = [PatternSpec(:no_any, "m", :warn, :flag, nothing)]

    # A typo'd capture would otherwise report under a name nobody wrote.
    q = compile_pattern_query(g, "(identifier) @no_anyy\n", "julia.patterns.scm")
    err = try
        check_declared_rules(q, specs, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("no_anyy", err.msg)
    @test occursin("[patterns.no_anyy]", err.msg)
    @test occursin("_", err.msg)   # points at the helper convention too

    # The declared rule, its `.not` companion, and a helper all pass.
    ok = compile_pattern_query(
        g, "(identifier) @no_any\n(identifier) @no_any.not\n((identifier) @_h (#eq? @_h \"x\"))\n",
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
