@testitem "user rule fires through analyze" setup = [Fixtures] tags = [:rules] begin
    using Dendro: analyze

    mktempdir() do dir
        path = joinpath(dir, "p.jl")
        write(path, "function f()\n    # BUG: broken\n    return 1\nend\n")

        # The default rule set does not know about it.
        @test !any(f -> f.metric == :bug_marker, analyze(path))

        # Appended to the set, it produces findings like any built-in flag.
        findings = analyze(path; rules = [Dendro.BUILTIN_RULES; Fixtures.BUG_RULE])
        @test any(f -> f.metric == :bug_marker, findings)
    end
end

@testitem "user rule is nameable in dendro-ignore" setup = [Fixtures] tags = [:rules] begin
    using Dendro: analyze, active

    rules = [Dendro.BUILTIN_RULES; Fixtures.BUG_RULE]

    mktempdir() do dir
        path = joinpath(dir, "p.jl")
        write(path, "function f()\n    # dendro-ignore: bug_marker\n    # BUG: broken\n    return 1\nend\n")

        findings = analyze(path; rules)
        @test any(f -> f.metric == :bug_marker && f.suppressed, findings)
        @test isempty(filter(f -> f.metric == :bug_marker, active(findings)))
    end

    # The active set validates the name, so the directive parses with no warning.
    src = "# dendro-ignore: bug_marker\nfunction f()\nend\n"
    d = only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl", rules))
    @test d.metrics == Set([:bug_marker])

    # Without the rule, the same name is unknown and warns.
    @test_logs (:warn,) Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl")
end

@testitem "a retuned band keeps a rule's unit scope" tags = [:rules] begin
    # `reband` rebuilds the rule around the project's band. Dropping `scope` there would
    # silently put `function_length` back on top-level code for any project that retunes
    # it, which is the one place the band is known not to transfer.
    config = Dendro.discover_config(String[]; use_files = false)
    config.bands[:function_length] = (10, 20)
    rules = Dendro.resolve_rules(config)
    len = only(filter(r -> r.name === :function_length, rules))
    @test len.band == (10, 20)
    @test len.scope === :callable
end

@testitem "the baseline samples only the units a rule measures" setup = [Fixtures] tags = [:rules] begin
    using TreeSitter

    src = "function f(x)\n    x\nend\n" * join(("a$(n) = $(n)" for n in 1:40), "\n") * "\n"
    tree = TreeSitter.parse(Dendro.parser_for(:julia), src)
    i = Dendro.build_index(tree, :julia, src, Dendro.query_for(:julia), Dendro.scopes_query_for(:julia))
    push!(
        i.units, Dendro.Unit(
            TreeSitter.Node[
                c for c in TreeSitter.named_children(TreeSitter.root(tree))
                    if !Dendro.is_function(c, i) && !(c in i.comment)
            ], 4, 43
        )
    )

    bl = Dendro.add_samples!(Dendro.Baseline(), i)
    # The definition alone: a top-level run's length must not move the distribution a
    # definition is ranked against.
    @test bl.samples[(:julia, :function_length)] == [3.0]
    # A rule that measures any unit sees both.
    @test length(bl.samples[(:julia, :cyclomatic)]) == 2
end
