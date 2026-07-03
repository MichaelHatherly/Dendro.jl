@testitem "is_suppressed" tags = [:suppress] begin
    Directive = Dendro.Directive

    # Same-line and preceding-line, all metrics.
    dirs = [Directive(5, nothing)]
    @test Dendro.is_suppressed(dirs, 5, :cyclomatic)
    @test Dendro.is_suppressed(dirs, 6, :cyclomatic)   # directly below
    @test !Dendro.is_suppressed(dirs, 4, :cyclomatic)
    @test !Dendro.is_suppressed(dirs, 7, :cyclomatic)

    # Metric-specific.
    dirs = [Directive(5, Set([:parameter_count]))]
    @test Dendro.is_suppressed(dirs, 5, :parameter_count)
    @test !Dendro.is_suppressed(dirs, 5, :cyclomatic)

    # File scope covers every line and, when unscoped, every metric.
    dirs = [Directive(:file, nothing)]
    @test Dendro.is_suppressed(dirs, 1, :cyclomatic)
    @test Dendro.is_suppressed(dirs, 999, :empty_catch)

    dirs = [Directive(:file, Set([:cyclomatic]))]
    @test Dendro.is_suppressed(dirs, 10, :cyclomatic)
    @test !Dendro.is_suppressed(dirs, 10, :parameter_count)

    @test !Dendro.is_suppressed(Dendro.Directive[], 1, :cyclomatic)
end

@testitem "suppressions parsing" setup = [Fixtures] tags = [:suppress] begin
    src = "# dendro-ignore\nfunction f()\nend\n"
    dirs = Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl")
    d = only(dirs)
    @test d.scope == 1
    @test d.metrics === nothing

    src = "# dendro-ignore: cyclomatic, parameter_count\nfunction f()\nend\n"
    d = only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
    @test d.scope == 1
    @test d.metrics == Set([:cyclomatic, :parameter_count])

    src = "# dendro-ignore-file\nfunction f()\nend\n"
    d = only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
    @test d.scope === :file
    @test d.metrics === nothing

    src = "# dendro-ignore-file: cyclomatic\nfunction f()\nend\n"
    d = only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
    @test d.scope === :file
    @test d.metrics == Set([:cyclomatic])

    src = "# just a comment\nfunction f()\nend\n"
    @test isempty(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
end

@testitem "reimplementation directive validates" setup = [Fixtures] tags = [:suppress] begin
    # The metric is emitted by a corpus pass, so its name must be in the
    # directive-validated set even though no Rule carries it.
    src = "# dendro-ignore: reimplementation\nfunction f()\nend\n"
    d = @test_logs only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
    @test d.metrics == Set([:reimplementation])
end

@testitem "suppressions typo guard" setup = [Fixtures] tags = [:suppress] begin
    src = "# dendro-ignore: cyclomatc\nfunction f()\nend\n"

    dirs = @test_logs (:warn,) Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl")
    # The unknown token is dropped, leaving a directive that suppresses nothing.
    @test only(dirs).metrics == Set{Symbol}()
end

@testitem "suppression directive with a reason" setup = [Fixtures] tags = [:suppress] begin
    # A reason after a `--` delimiter is ignored, with no warning.
    src = "# dendro-ignore: cyclomatic -- it is a dispatch table\nfunction f()\nend\n"
    d = only(Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl"))
    @test d.metrics == Set([:cyclomatic])

    # A recognized metric still applies when followed by stray prose, rather
    # than silently suppressing nothing. The prose words warn.
    src = "# dendro-ignore: cyclomatic generated\nfunction f()\nend\n"
    dirs = @test_logs (:warn,) Dendro.suppressions(Fixtures.idx(:julia, src); file = "x.jl")
    @test :cyclomatic in only(dirs).metrics
end

@testitem "suppression integration (julia)" tags = [:suppress] begin
    mktempdir() do dir
        # Preceding-line directive on a 6-parameter function suppresses only that
        # metric; other findings on the function survive.
        path = joinpath(dir, "p.jl")
        write(path, "# dendro-ignore: parameter_count\nfunction f(a, b, c, d, e, f)\n    1\nend\n")
        findings = Dendro.analyze(path)
        @test count(f -> f.suppressed, findings) == 1
        pc = only(filter(f -> f.metric == :parameter_count, findings))
        @test pc.suppressed
        @test isempty(filter(f -> f.metric == :parameter_count, Dendro.active(findings)))

        # Same-line directive on a swallowed catch.
        path = joinpath(dir, "c.jl")
        write(path, "function f()\n    try\n        g()\n    catch  # dendro-ignore: empty_catch\n    end\nend\n")
        findings = Dendro.analyze(path)
        @test isempty(filter(f -> f.metric == :empty_catch, Dendro.active(findings)))
        @test any(f -> f.metric == :empty_catch && f.suppressed, findings)

        # Whole-file directive empties active.
        path = joinpath(dir, "f.jl")
        write(path, "# dendro-ignore-file\nfunction f(a, b, c, d, e, f)\n    1\nend\n")
        findings = Dendro.analyze(path)
        @test !isempty(findings)
        @test isempty(Dendro.active(findings))
    end
end

@testitem "unused-binding findings are suppressible" tags = [:suppress] begin
    mktempdir() do dir
        # An unused parameter accepted for an interface's sake.
        path = joinpath(dir, "p.jl")
        write(path, "# dendro-ignore: unused_parameter\nfunction f(x, y)\n    return x\nend\n")
        findings = Dendro.analyze(path)
        @test any(f -> f.metric == :unused_parameter && f.suppressed, findings)
        @test isempty(filter(f -> f.metric == :unused_parameter, Dendro.active(findings)))

        # An unused local kept deliberately.
        path = joinpath(dir, "l.jl")
        write(path, "function f()\n    x = g()  # dendro-ignore: unused_local\n    return 1\nend\n")
        findings = Dendro.analyze(path)
        @test any(f -> f.metric == :unused_local && f.suppressed, findings)
        @test isempty(filter(f -> f.metric == :unused_local, Dendro.active(findings)))
    end
end

@testitem "suppression is language-agnostic" tags = [:suppress] begin
    mktempdir() do dir
        # Python: a hash comment.
        py = joinpath(dir, "p.py")
        write(py, "# dendro-ignore: parameter_count\ndef f(a, b, c, d, e, f):\n    return 1\n")
        findings = Dendro.analyze(py)
        @test isempty(filter(f -> f.metric == :parameter_count, Dendro.active(findings)))

        # JavaScript: a slash comment.
        js = joinpath(dir, "p.js")
        write(js, "// dendro-ignore: parameter_count\nfunction f(a, b, c, d, e, f) {\n  return 1;\n}\n")
        findings = Dendro.analyze(js)
        @test isempty(filter(f -> f.metric == :parameter_count, Dendro.active(findings)))
    end
end

@testitem "report suppression footer" tags = [:suppress] begin
    mktempdir() do dir
        path = joinpath(dir, "p.jl")
        write(path, "# dendro-ignore: parameter_count\nfunction f(a, b, c, d, e, f)\n    1\nend\n")
        findings = Dendro.analyze(path)

        io = IOBuffer()
        show(io, MIME("text/plain"), findings)
        out = String(take!(io))
        @test occursin("1 finding", out)
        @test occursin("suppressed", out)
        @test !occursin("parameter_count", out)   # the only suppressed finding is hidden
    end
end
