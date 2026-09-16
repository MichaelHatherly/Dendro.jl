@testitem "analyze absolute findings" tags = [:report] begin
    mktempdir() do dir
        path = joinpath(dir, "c.jl")
        write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")

        findings = Dendro.analyze(path)
        hit = only(filter(x -> x.metric == :parameter_count, findings))
        @test hit.value == 6
        @test hit.absolute == :warn
        # The file's lone function is the whole corpus, so it ranks at the top.
        @test hit.percentile == 1.0
        @test hit.kind == :scalar
        @test first(hit.locations).unit == "f"
        @test first(hit.locations).line == 1
    end
end

@testitem "analyze relative findings" tags = [:report] begin
    mktempdir() do dir
        path = joinpath(dir, "g.jl")
        write(path, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

        # The file auto-builds its own baseline; the lone function ranks at the top
        # even though its complexity is well within the absolute band.
        findings = Dendro.analyze(path; cut = 0.95)
        hit = only(filter(x -> x.metric == :cyclomatic, findings))
        @test hit.value == 2
        @test hit.absolute == :ok
        @test hit.percentile == 1.0
    end
end

@testitem "analyze flag findings" tags = [:report] begin
    mktempdir() do dir
        swallow = joinpath(dir, "s.jl")
        write(swallow, "function f()\n    try\n        g()\n    catch\n    end\nend\n")
        @test any(x -> x.metric == :empty_catch, Dendro.analyze(swallow))

        todo = joinpath(dir, "t.jl")
        write(todo, "function f()\n    # TODO: finish\n    1\nend\n")
        @test any(x -> x.metric == :stub_marker, Dendro.analyze(todo))

        stub = joinpath(dir, "e.jl")
        write(stub, "function g()\nend\n")
        @test any(x -> x.metric == :empty_body, Dendro.analyze(stub))
    end
end

@testitem "analyze language argument forms" tags = [:report] begin
    mktempdir() do dir
        path = joinpath(dir, "snippet.txt")   # extension is not recognised
        write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")

        # A given language resolves the same whether a symbol or string, any case.
        for lang in (:julia, "julia", :Julia, "JULIA")
            findings = Dendro.analyze(path; language = lang)
            @test any(x -> x.metric == :parameter_count && first(x.locations).unit == "f", findings)
        end
    end
end

# A location spans a region, not a point, and the region is what the verbosity score
# measures. The short constructors keep naming a single line, since most of the sites
# building one have no span to give.
@testitem "a location spans from its line to its last" tags = [:report] begin
    @test Dendro.Location("f.jl", 7, "g").lastline == 7
    @test Dendro.Location("f.jl", 7, "g", "toward h.jl").lastline == 7

    mktempdir() do dir
        # A scalar finding spans its unit, and a flag finding the node it fired on. The
        # catch clause runs lines 4 to 5, so both readings are wider than their first line.
        path = joinpath(dir, "c.jl")
        write(path, "function f(a, b, c, d, e, g)\n    try\n        h(a)\n    catch\n    end\nend\n")
        findings = Dendro.analyze(path)

        scalar = first(only(filter(x -> x.metric == :parameter_count, findings)).locations)
        @test (scalar.line, scalar.lastline) == (1, 6)

        flag = first(only(filter(x -> x.metric == :empty_catch, findings)).locations)
        @test (flag.line, flag.lastline) == (4, 5)
    end
end

@testitem "report formatting" tags = [:report] begin
    mktempdir() do dir
        path = joinpath(dir, "c.jl")
        write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")
        findings = Dendro.analyze(path)

        io = IOBuffer()
        show(io, MIME("text/plain"), findings)
        out = String(take!(io))
        @test occursin("parameter_count", out)
        @test occursin("c.jl:1", out)
    end
end

# What a bundle costs when it stays in: its minified helpers repeat, so `:duplicate` fires
# at the error band on code nobody wrote, and its callables fill the sample every percentile
# is taken against. Both are what the parse boundary turning it away prevents.
@testitem "a bundle leaves the findings and the corpus scores" tags = [:report] begin
    mktempdir() do dir
        bundle = "var f = __webpack_require__(1);\nfunction m(a, b) {\n  var c = a + b;\n  return c * 2;\n}\n"
        write(joinpath(dir, "one.bundle.js"), bundle)
        write(joinpath(dir, "two.bundle.js"), bundle)
        write(joinpath(dir, "app.js"), "function add(a, b) {\n  return a + b;\n}\n")

        findings = @test_logs (:warn,) match_mode = :any Dendro.analyze(dir; min_size = 1)
        @test isempty(filter(f -> f.metric === :duplicate, findings))
        @test findings.summary.now.callables == 1
        @test length(findings.generated) == 2
    end
end

@testitem "the report closes with the files excluded as generated" tags = [:report] begin
    mktempdir() do dir
        write(joinpath(dir, "b.js"), "var f = __webpack_require__(1);\nfunction g(x) { return f(x); }\n")
        write(joinpath(dir, "p.py"), "# Generated by a code generator\ndef h(x):\n    return x\n")
        write(joinpath(dir, "app.js"), "function add(a, b) {\n  return a + b;\n}\n")

        findings = @test_logs (:warn,) match_mode = :any Dendro.analyze(dir)
        io = IOBuffer()
        show(io, MIME("text/plain"), findings)
        out = String(take!(io))
        @test occursin("2 file(s) excluded as generated (", out)
        @test occursin("__webpack_require__", out)
        @test occursin("Generated by", out)

        # A directive accepts a finding and says nothing about which files were read, so
        # the active view keeps the list. The gate is a finding-set difference and carries
        # none of it.
        @test Dendro.active(findings).generated == findings.generated
        @test isempty((@test_logs (:warn,) match_mode = :any Dendro.errors(dir)).generated)
    end
end

@testitem "github annotations" tags = [:report] begin
    mktempdir() do dir
        # A warn-band scalar renders a ::warning line anchored at the unit, with a
        # title property whose colon is percent-escaped.
        warnpath = joinpath(dir, "c.jl")
        write(warnpath, "function f(a, b, c, d, e, f)\n    1\nend\n")
        io = IOBuffer()
        Dendro.github_annotations(io, Dendro.analyze(warnpath))
        out = String(take!(io))
        line = only(filter(l -> occursin("parameter_count", l), split(strip(out), "\n")))
        @test startswith(line, "::warning ")
        @test occursin("file=$(Dendro.escape_prop(warnpath))", line)
        @test occursin("line=1", line)
        @test occursin("title=Dendro%3A parameter_count", line)
        @test occursin("parameter_count 6", line)

        # A flag (always high band) renders ::error.
        flagpath = joinpath(dir, "e.jl")
        write(flagpath, "function g()\nend\n")
        io = IOBuffer()
        Dendro.github_annotations(io, Dendro.analyze(flagpath))
        out = String(take!(io))
        @test occursin("::error ", out)
        @test occursin("empty_body", out)

        # Suppressed findings are skipped; an unsuppressed finding in the same file
        # still renders. The metric-scoped directive mutes parameter_count, leaving
        # empty_body to fire.
        suppath = joinpath(dir, "s.jl")
        write(suppath, "# dendro-ignore: parameter_count\nfunction f(a, b, c, d, e, f)\nend\n")
        findings = Dendro.analyze(suppath)
        io = IOBuffer()
        Dendro.github_annotations(io, findings)
        out = String(take!(io))
        @test occursin("empty_body", out)
        @test !occursin("parameter_count", out)

        # One line per non-suppressed finding: no message injects a newline.
        lines = filter(!isempty, split(out, "\n"))
        @test length(lines) == count(f -> !f.suppressed, findings)
    end
end
