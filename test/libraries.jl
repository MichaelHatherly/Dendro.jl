@testitem "Library derives a name from its root" tags = [:libraries] begin
    mktempdir() do dir
        src = joinpath(dir, "IterTools", "src")
        ext = joinpath(dir, "IterTools", "ext")
        mkpath(src)
        mkpath(ext)

        # A conventional source directory names the package above it, not itself.
        @test Dendro.Library(src).name == "IterTools"
        @test Dendro.Library(ext).name == "ext"
        @test Dendro.Library("Named", src).name == "Named"
        @test Dendro.Library("Named", [src, ext]).roots == [src, ext]
    end
end

@testitem "Library resolves and validates its roots" tags = [:libraries] begin
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(src)
        cd(dir) do
            # A relative root resolves against the process directory, so the API and the
            # config agree on what a path means.
            root = only(Dendro.Library("src").roots)
            @test isabspath(root)
            @test realpath(root) == realpath(src)
        end
        @test_throws ErrorException Dendro.Library(joinpath(dir, "missing"))
        write(joinpath(dir, "f.jl"), "f() = 1\n")
        @test_throws ErrorException Dendro.Library(joinpath(dir, "f.jl"))
    end
end

@testitem "config reads [libraries] tables" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        one = joinpath(dir, "one", "src")
        two = joinpath(dir, "two", "src")
        mkpath(one)
        mkpath(two)
        write(
            joinpath(dir, ".dendro.toml"), """
            [libraries.One]
            path = "one/src"

            [libraries.Both]
            paths = ["one/src", "two/src"]
            ignore = ["gen.jl"]
            """
        )

        cfg = Fixtures.isolated_config([dir], joinpath(dir, ".dendro.toml"))
        libs = Dict(l.name => l for l in cfg.libraries)
        @test sort(collect(keys(libs))) == ["Both", "One"]
        # Relative paths resolve against the config file's own directory.
        @test realpath.(libs["One"].roots) == [realpath(one)]
        @test realpath.(libs["Both"].roots) == [realpath(one), realpath(two)]
        @test libs["Both"].ignore == ["gen.jl"]
    end
end

@testitem "a [libraries] path glob expands across a version slug" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        slug = joinpath(dir, "depot", "IterTools", "A1b2C", "src")
        mkpath(slug)
        write(
            joinpath(dir, ".dendro.toml"), """
            [libraries.IterTools]
            path = "depot/IterTools/*/src"
            """
        )

        cfg = Fixtures.isolated_config([dir], joinpath(dir, ".dendro.toml"))
        @test realpath.(only(cfg.libraries).roots) == [realpath(slug)]
    end
end

@testitem "a [libraries] path matching nothing is an error" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        write(
            joinpath(dir, ".dendro.toml"), """
            [libraries.Gone]
            path = "depot/*/src"
            """
        )
        @test_throws Dendro.ConfigError Fixtures.isolated_config([dir], joinpath(dir, ".dendro.toml"))
    end
end

@testitem "an unknown [libraries] key warns and is dropped" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        mkpath(joinpath(dir, "src"))
        write(
            joinpath(dir, ".dendro.toml"), """
            [libraries.One]
            path = "src"
            depth = 3
            """
        )

        cfg = @test_logs (:warn,) Fixtures.isolated_config([dir], joinpath(dir, ".dendro.toml"))
        @test only(cfg.libraries).name == "One"
    end
end

@testitem "an exact match against a public library function gates" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )

        hit = only(Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate))
        @test hit.kind == :flag
        @test hit.absolute == :high
        # The whole of the project's function is in the library, so coverage is 100.
        @test hit.value == 100
        # One location, in the project. Every library fact is evidence in the label.
        loc = only(hit.locations)
        @test loc.file == joinpath(proj, "util.jl")
        @test loc.unit == "chunk_by"
        @test occursin("dep.partition public", loc.label)
        @test occursin("Dep.jl:", loc.label)
    end
end

@testitem "a match against a private library function only warns" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(String[], Fixtures.chain("partition", 6))],
        )

        hit = only(Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate))
        @test hit.absolute == :warn
        @test hit.value == 100
        @test occursin("internal", only(hit.locations).label)
    end
end

@testitem "a block matching inside a library function warns and names the symbol" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["parse.jl" => Fixtures.nested_chain("read_header", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )

        hit = only(Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate))
        # Half a function cannot be imported, so a block match never gates however public
        # the function containing it.
        @test hit.absolute == :warn
        @test 0 < hit.value < 100
        @test occursin("dep.partition public", only(hit.locations).label)
    end
end

@testitem "a whole-unit match is not reported again for each block inside it" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )

        hits = Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate)
        # The function's body block matches too; maximality keeps the larger region only.
        @test length(hits) == 1
    end
end

@testitem "a library whose language has no linkage never gates" setup = [Fixtures] tags = [:libraries] begin
    fn(name, a, b) = string(
        "$name() {\n  local $a=0\n  for item in \$1; do\n    $a=\$(($a + item))\n  done\n",
        "  local $b=\$(($a + \$2))\n  echo \"\$$b\"\n}\n"
    )

    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.sh" => fn("total_price", "subtotal", "grand")],
            library = ["dep.sh" => fn("final_amount", "accum", "sum")],
        )

        hits = Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate)
        # Bash has no `LINKAGES` entry, so nothing can say a definition is public. That
        # reads as private here, the opposite of `:unreferenced`'s default, because public
        # is what promotes a finding into the gate.
        @test !isempty(hits)
        @test all(f -> f.absolute == :warn, hits)
    end
end

@testitem "a library in another language reports nothing" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["dep.py" => Fixtures.pychain("chunk_by", 6)],
        )

        @test isempty(Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_duplicate))
    end
end

@testitem "dendro-ignore suppresses a library duplicate and keeps counting it" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => "# dendro-ignore: library_duplicate\n" * Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )

        findings = Dendro.analyze(proj; libraries = [lib])
        @test only(Fixtures.of_metric(findings, :library_duplicate)).suppressed
        @test isempty(Fixtures.of_metric(Dendro.active(findings), :library_duplicate))
    end
end

@testitem "a library root inside the scanned corpus is dropped" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(src)
        write(joinpath(src, "util.jl"), Fixtures.chain("chunk_by", 6))

        # Pointing a library at the project's own source would otherwise report every
        # function as a duplicate of itself.
        @test isempty(Fixtures.of_metric(Dendro.analyze(src; libraries = [src]), :library_duplicate))
    end
end

@testitem "no libraries leaves the scan unchanged" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(src)
        write(joinpath(src, "util.jl"), Fixtures.chain("chunk_by", 6))

        plain = sprint(show, MIME"text/plain"(), Dendro.analyze(src))
        empty = sprint(show, MIME"text/plain"(), Dendro.analyze(src; libraries = Dendro.Library[]))
        @test plain == empty
        @test !occursin("library_", plain)
    end
end

@testitem "library findings survive diff scoping and keep a stable ratchet key" setup = [Fixtures] tags = [:libraries] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "util.jl"), Fixtures.chain("chunk_by", 6))
    Fixtures.commit!(root, "base")

    mktempdir() do dir
        lib = joinpath(dir, "dep", "src")
        mkpath(lib)
        write(joinpath(lib, "Dep.jl"), Fixtures.libmod(["partition"], Fixtures.chain("partition", 6)))

        # A library site is never a `Location`, so `Scope.rels` has every path a finding
        # names and the diff scope resolves rather than throwing a `KeyError`.
        @test Dendro.analyze(src; base = "HEAD", libraries = [lib]) isa Dendro.Findings

        hit = only(Fixtures.of_metric(Dendro.analyze(src; libraries = [lib]), :library_duplicate))
        rels = Dict{String, String}()
        first_key = Dendro.fkey(hit, root, rels)

        moved = joinpath(dir, "dep-2.0", "src")
        mkpath(moved)
        cp(joinpath(lib, "Dep.jl"), joinpath(moved, "Dep.jl"))
        again = only(Fixtures.of_metric(Dendro.analyze(src; libraries = [moved]), :library_duplicate))
        # Upgrading a dependency moves its path and its version slug; the ratchet key does
        # not mention either, so an unchanged finding is never re-reported.
        @test Dendro.fkey(again, root, Dict{String, String}()) == first_key
    end
end

@testitem "[clones] carries the library thresholds" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        write(
            joinpath(dir, ".dendro.toml"), """
            [clones]
            library_threshold     = 0.7
            library_gate_coverage = 80
            """
        )

        cfg = Fixtures.isolated_config([dir], joinpath(dir, ".dendro.toml"))
        @test cfg.library_threshold == 0.7
        @test cfg.library_gate_coverage == 80
    end
end
