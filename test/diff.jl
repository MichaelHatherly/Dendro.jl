@testset "changed_ranges" begin
    diff = """
    diff --git a/foo.jl b/foo.jl
    index 1111111..2222222 100644
    --- a/foo.jl
    +++ b/foo.jl
    @@ -1,3 +1,5 @@
     line
    +added1
    +added2
     line
    @@ -10,2 +12,3 @@
     x
    +y
    """
    ranges = Dendro.changed_ranges(diff)
    @test ranges["foo.jl"] == [2:3, 13:13]
end

@testset "analyze_diff (julia)" begin
    repo = mktempdir()
    run(`git -C $repo init -q`)
    file = joinpath(repo, "m.jl")
    write(file, "function f(x)\n    x\nend\n")
    run(`git -C $repo add -A`)
    run(`git -C $repo -c user.email=t@example.com -c user.name=t commit -q -m init`)

    # Add a new function with too many parameters; leave f untouched.
    write(file, "function f(x)\n    x\nend\nfunction g(a, b, c, d, e, f)\n    1\nend\n")
    findings = Dendro.analyze_diff(; repo = repo)

    @test any(x -> x.unit == "g" && x.metric == :parameter_count, findings)
    # f was not in the changed range, so it must not be reported.
    @test !any(x -> x.unit == "f", findings)
end
