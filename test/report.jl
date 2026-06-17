@testset "analyze absolute findings" begin
    dir = mktempdir()
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

@testset "analyze relative findings" begin
    dir = mktempdir()
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

@testset "analyze flag findings" begin
    dir = mktempdir()
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

@testset "analyze language argument forms" begin
    dir = mktempdir()
    path = joinpath(dir, "snippet.txt")   # extension is not recognised
    write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")

    # A given language resolves the same whether a symbol or string, any case.
    for lang in (:julia, "julia", :Julia, "JULIA")
        findings = Dendro.analyze(path; language = lang)
        @test any(x -> x.metric == :parameter_count && first(x.locations).unit == "f", findings)
    end
end

@testset "report formatting" begin
    dir = mktempdir()
    path = joinpath(dir, "c.jl")
    write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")
    findings = Dendro.analyze(path)

    io = IOBuffer()
    show(io, MIME("text/plain"), findings)
    out = String(take!(io))
    @test occursin("parameter_count", out)
    @test occursin("c.jl:1", out)
end
