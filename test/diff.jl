# The line-range vocabulary is exercised through the scope it builds. Reading a revision
# into those ranges is `git.jl`'s job and is tested in `test/git.jl`.

@testitem "analyze with base scopes to changed functions" tags = [:diff] begin
    using Dendro: analyze

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
