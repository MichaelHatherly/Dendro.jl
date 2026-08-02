# The git layer reads repositories through libgit2, so `--base` and `--since` work
# where the `git` and `tar` binaries are absent. Each item builds its fixture with the
# binary, then strips `PATH` around the call under test: the assertion is that Dendro
# never shells out, and a subprocess is the one thing an empty `PATH` reliably breaks.

# No binary on `PATH`, so a subprocess cannot spawn. "/nonexistent" rather than "" since
# an empty `PATH` falls back to a system default on some platforms.
@testitem "git_toplevel finds the root without the git binary" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    expected = realpath(root)
    got = withenv("PATH" => "/nonexistent") do
        Dendro.git_toplevel(src)
    end
    @test realpath(got) == expected
end

# A path inside the repo but below its root resolves to the root, not to itself: the
# scope keys every relative path against this, so a subdirectory scan must agree with a
# whole-repo one.
@testitem "git_toplevel resolves from a subdirectory" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    nested = joinpath(src, "deep")
    mkpath(nested)
    got = withenv("PATH" => "/nonexistent") do
        Dendro.git_toplevel(nested)
    end
    @test realpath(got) == realpath(root)
end

# The base corpus is the committed content, never the working tree: the ratchet compares
# a revision against what is on disk now, so reading the file back must give what was
# committed even though the working copy has moved on.
@testitem "with_base_corpus materialises a ref without the git binary" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f() = 1\n")
    Fixtures.commit!(root, "init")
    write(joinpath(src, "a.jl"), "f() = 2\n")

    got = withenv("PATH" => "/nonexistent") do
        Dendro.with_base_corpus([src], "HEAD", realpath(root)) do troot, tpaths
            read(joinpath(first(tpaths), "a.jl"), String)
        end
    end
    @test got == "f() = 1\n"
end

# Nested directories have to be created on the way down, and a file added after the ref
# must be absent from the base rather than carried over from the working tree.
@testitem "with_base_corpus reproduces nested paths and omits later files" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    mkpath(joinpath(src, "deep", "deeper"))
    write(joinpath(src, "deep", "deeper", "b.jl"), "g() = 1\n")
    Fixtures.commit!(root, "init")
    write(joinpath(src, "later.jl"), "h() = 1\n")

    nested, later = withenv("PATH" => "/nonexistent") do
        Dendro.with_base_corpus([src], "HEAD", realpath(root)) do troot, tpaths
            base = first(tpaths)
            (isfile(joinpath(base, "deep", "deeper", "b.jl")), isfile(joinpath(base, "later.jl")))
        end
    end
    @test nested
    @test !later
end

# A root that did not exist at the ref is the paths-are-new case, not a failure: the
# callback sees an empty vector rather than a phantom corpus.
@testitem "with_base_corpus drops a root absent at the ref" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f() = 1\n")
    Fixtures.commit!(root, "init")
    fresh = joinpath(root, "added")
    mkpath(fresh)
    write(joinpath(fresh, "c.jl"), "k() = 1\n")

    got = withenv("PATH" => "/nonexistent") do
        Dendro.with_base_corpus([fresh], "HEAD", realpath(root)) do troot, tpaths
            tpaths
        end
    end
    @test isempty(got)
end

# A broken ref is misconfiguration and must not degrade into an empty base that reads as
# "everything is new". The message names the caller's own option, not an internal one.
@testitem "with_base_corpus errors on an unknown ref, naming the keyword" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f() = 1\n")
    Fixtures.commit!(root, "init")

    err = try
        withenv("PATH" => "/nonexistent") do
            Dendro.with_base_corpus([src], "no-such-ref", realpath(root), "since") do troot, tpaths
                nothing
            end
        end
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("since", err.msg)
    @test occursin("no-such-ref", err.msg)
end

# The libgit2 reading has to agree with the unified-diff parser it replaces, over the
# shapes a real edit produces: several hunks in one file, an added file, a deleted one, a
# path with a space, and a binary file with no hunks at all. A wrong `DiffLine` layout
# reads plausible-looking line numbers rather than failing, so this equivalence is the
# check that catches it.
@testitem "changed_ranges agrees with the git diff parser" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "many.jl"), string("f() = 1\n", "x\n"^20))
    write(joinpath(src, "gone.jl"), "g() = 1\n")
    write(joinpath(src, "a name.jl"), "h() = 1\n")
    write(joinpath(src, "bin.dat"), UInt8[0x00, 0x01, 0x02, 0x00])
    Fixtures.commit!(root, "init")

    # Two separated hunks, so a single-hunk reading would not pass.
    lines = collect(eachline(joinpath(src, "many.jl")))
    insert!(lines, 2, "added_near_top")
    insert!(lines, 15, "added_lower")
    write(joinpath(src, "many.jl"), join(lines, "\n") * "\n")
    rm(joinpath(src, "gone.jl"))
    write(joinpath(src, "a name.jl"), "h() = 1\nh2() = 2\n")
    write(joinpath(src, "bin.dat"), UInt8[0x00, 0x09, 0x02, 0x00])
    write(joinpath(src, "fresh.jl"), "k() = 1\nk2() = 2\n")

    expected = Dendro.changed_ranges(read(`git -C $root diff HEAD`, String))
    got = withenv("PATH" => "/nonexistent") do
        Dendro.changed_ranges(realpath(root), "HEAD")
    end
    @test got == expected
    # Guard the oracle itself: an empty `expected` would make the comparison vacuous.
    @test haskey(expected, "src/many.jl")
    @test haskey(expected, "src/a name.jl")
    @test !haskey(expected, "src/gone.jl")
end

# A working tree matching the ref has nothing to report, and an empty result must be an
# empty Dict rather than an error or a phantom entry.
@testitem "changed_ranges is empty for an unchanged tree" tags = [:git] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f() = 1\n")
    Fixtures.commit!(root, "init")

    got = withenv("PATH" => "/nonexistent") do
        Dendro.changed_ranges(realpath(root), "HEAD")
    end
    @test isempty(got)
end
