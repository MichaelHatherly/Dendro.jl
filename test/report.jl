@testset "analyze absolute findings" begin
    dir = mktempdir()
    path = joinpath(dir, "c.jl")
    write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")

    findings = Dendro.analyze(path)
    hit = only(filter(x -> x.metric == :parameter_count, findings))
    @test hit.value == 6
    @test hit.absolute == :warn
    @test hit.percentile === nothing
    @test hit.kind == :scalar
    @test hit.unit == "f"
    @test hit.line == 1
end

@testset "analyze relative findings" begin
    dir = mktempdir()
    path = joinpath(dir, "g.jl")
    write(path, "function g(x)\n    if x > 0\n        1\n    end\nend\n")

    # Corpus where every function has complexity 1; complexity 2 is an outlier
    # even though it is well within the absolute band.
    b = Dendro.Baseline(Dict((:julia, :cyclomatic) => fill(1.0, 10)))
    findings = Dendro.analyze(path; baseline = b, cut = 0.95)
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

@testset "report formatting" begin
    dir = mktempdir()
    path = joinpath(dir, "c.jl")
    write(path, "function f(a, b, c, d, e, f)\n    1\nend\n")
    findings = Dendro.analyze(path)

    io = IOBuffer()
    Dendro.report(io, findings)
    out = String(take!(io))
    @test occursin("parameter_count", out)
    @test occursin("c.jl:1", out)
end
