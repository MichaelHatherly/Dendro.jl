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

@testset "changed_ranges keys a path containing a space" begin
    # Git terminates a header path that contains a space with a tab. The key must
    # be the bare path, or diff-scoping never matches it against the file.
    diff = "diff --git a/a b.jl b/a b.jl\nindex 1111111..2222222 100644\n--- a/a b.jl\t\n+++ b/a b.jl\t\n@@ -1,1 +1,2 @@\n x\n+y\n"
    ranges = Dendro.changed_ranges(diff)
    @test collect(keys(ranges)) == ["a b.jl"]
    @test ranges["a b.jl"] == [2:2]
end

@testset "changed_ranges skips a combined-diff header" begin
    # A combined diff (`@@@`, from a merge conflict) is not the two-side format the
    # parser reads. It must skip the header, not crash dereferencing a failed match.
    diff = "diff --cc f.txt\nindex 1111111,2222222..0000000\n--- a/f.txt\n+++ b/f.txt\n@@@ -1,3 -1,3 +1,9 @@@\n  a\n++x\n"
    @test Dendro.changed_ranges(diff) isa Dict
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
