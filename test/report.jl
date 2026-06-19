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
