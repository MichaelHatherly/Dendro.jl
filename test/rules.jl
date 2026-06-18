# A custom flag rule a caller might supply: comments carrying a BUG marker. Mirrors
# the built-in stub_marker rule, but names a metric Dendro does not ship.
bug_markers(index) =
    [n for n in index.comment.nodes if occursin("BUG", TreeSitter.slice(index.source, n))]

const BUG_RULE = Dendro.Rule(:bug_marker, :flag, nothing, bug_markers)

@testset "user rule fires through analyze" begin
    mktempdir() do dir
        path = joinpath(dir, "p.jl")
        write(path, "function f()\n    # BUG: broken\n    return 1\nend\n")

        # The default rule set does not know about it.
        @test !any(f -> f.metric == :bug_marker, analyze(path))

        # Appended to the set, it produces findings like any built-in flag.
        findings = analyze(path; rules = [Dendro.BUILTIN_RULES; BUG_RULE])
        @test any(f -> f.metric == :bug_marker, findings)
    end
end

@testset "user rule is nameable in dendro-ignore" begin
    rules = [Dendro.BUILTIN_RULES; BUG_RULE]

    mktempdir() do dir
        path = joinpath(dir, "p.jl")
        write(path, "function f()\n    # dendro-ignore: bug_marker\n    # BUG: broken\n    return 1\nend\n")

        findings = analyze(path; rules)
        @test any(f -> f.metric == :bug_marker && f.suppressed, findings)
        @test isempty(filter(f -> f.metric == :bug_marker, active(findings)))
    end

    # The active set validates the name, so the directive parses with no warning.
    src = "# dendro-ignore: bug_marker\nfunction f()\nend\n"
    d = only(Dendro.suppressions(idx(:julia, src); file = "x.jl", rules))
    @test d.metrics == Set([:bug_marker])

    # Without the rule, the same name is unknown and warns.
    @test_logs (:warn,) Dendro.suppressions(idx(:julia, src); file = "x.jl")
end
