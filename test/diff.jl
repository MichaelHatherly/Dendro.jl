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

@testset "changed_ranges does not mistake added content for headers" begin
    # An added line whose content begins with `++ ` reads as `+++ ` in the diff,
    # and one beginning with `@@` reads as a hunk header. Neither is a header
    # here: the hunk's line counts decide what is body.
    diff = """
    diff --git a/t.txt b/t.txt
    index 1111111..2222222 100644
    --- a/t.txt
    +++ b/t.txt
    @@ -1,1 +1,4 @@
     intro
    +normal
    +++ looks like a header
    +@@ looks like a hunk
    """
    ranges = Dendro.changed_ranges(diff)
    @test collect(keys(ranges)) == ["t.txt"]
    @test ranges["t.txt"] == [2:4]
end

@testset "changed_ranges tracks deletions and context" begin
    # Removed lines advance the old side only; the hunk ends by its line counts.
    diff = """
    diff --git a/m.jl b/m.jl
    index 1111111..2222222 100644
    --- a/m.jl
    +++ b/m.jl
    @@ -1,3 +1,2 @@
     keep
    -gone
    -also gone
    +fresh
    """
    ranges = Dendro.changed_ranges(diff)
    @test ranges["m.jl"] == [2:2]   # `fresh` lands at new-file line 2
end

@testset "analyze with base scopes to changed functions" begin
    mktempdir() do repo
        run(`git -C $repo init -q`)
        file = joinpath(repo, "m.jl")
        write(file, "function f(x)\n    x\nend\n")
        run(`git -C $repo add -A`)
        run(`git -C $repo -c user.email=t@example.com -c user.name=t commit -q -m init`)

        # Add a new function with too many parameters; leave f untouched.
        write(file, "function f(x)\n    x\nend\nfunction g(a, b, c, d, e, f)\n    1\nend\n")
        findings = analyze(repo; base = "HEAD")

        @test any(x -> first(x.locations).unit == "g" && x.metric == :parameter_count, findings)
        # f was not in the changed range, so it must not be reported.
        @test !any(x -> first(x.locations).unit == "f", findings)
    end
end
