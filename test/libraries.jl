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

@testitem "an edited copy of a library function is a near duplicate" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 9)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )

        findings = Dendro.analyze(proj; libraries = [lib])
        # One added statement changes the shape, so the exact join misses it entirely.
        @test isempty(Fixtures.of_metric(findings, :library_duplicate))

        hit = only(Fixtures.of_metric(findings, :library_near_duplicate))
        @test hit.kind == :flag
        # Never `:high`, whatever the evidence: measured precision on this pass's would-be
        # gate findings was a third of the exact pass's, so it proposes and never gates.
        @test hit.absolute == :warn
        # Coverage is the LCS against the project's own unit, so the statement the copy
        # added is what it falls short of 100 by.
        @test 80 <= hit.value < 100
        @test occursin("dep.partition public", only(hit.locations).label)
        # So nothing this pass reports ever reaches the gate.
        errs = Dendro.errors(proj; libraries = [lib])
        @test isempty(Fixtures.of_metric(errs, :library_near_duplicate))
    end
end

@testitem "an exact library match is not reported again as a near duplicate" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 8)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )

        findings = Dendro.analyze(proj; libraries = [lib])
        @test length(Fixtures.of_metric(findings, :library_duplicate)) == 1
        @test isempty(Fixtures.of_metric(findings, :library_near_duplicate))
    end
end

@testitem "anchor grain finds an edited copy of a library function inside a larger one" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            # Padded far enough that the enclosing function lands two size bands above the
            # library function, so the unit-grain query never proposes the pair.
            project = ["parse.jl" => Fixtures.nested_chain("read_header", 9; pad = 40)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )

        # At unit grain the two are compared whole, and a block inside a much larger
        # function is not a near-miss of it.
        plain = Fixtures.of_metric(Dendro.analyze(proj; libraries = [lib]), :library_near_duplicate)
        @test isempty(plain)

        write(joinpath(dir, "proj", ".dendro.toml"), "[clones]\nlibrary_anchor_grain = true\n")
        cfg = Fixtures.isolated_config([proj], joinpath(dir, "proj", ".dendro.toml"))
        @test cfg.library_anchor_grain

        hit = only(Fixtures.of_metric(Dendro.analyze(proj; config = cfg, libraries = [lib]), :library_near_duplicate))
        # The coverage denominator stays the project's whole enclosing unit, so a block
        # match scores what the edit would actually remove.
        @test 0 < hit.value < 100
        @test hit.absolute == :warn
        @test occursin("dep.partition public", only(hit.locations).label)
    end
end

@testitem "anchor grain keys the reference cache apart from unit grain" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                units = Dendro.reference_index(library; min_size = 10, grain = :unit)
                anchors = Dendro.reference_index(library; min_size = 10, grain = :anchor)
                # A unit-grain index carries no features on its block anchors, so serving one
                # to the anchor-grain pass would silently under-report.
                @test length(Fixtures.cache_entries(cache)) == 2
                @test all(isempty(a.sequence) for a in units.anchors if !a.whole_unit)
                @test all(!isempty(a.sequence) for a in anchors.anchors)
            end
        end
    end
end

@testitem "a dissimilar project function matches no library function" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.guards("chunk_by", 8)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )

        findings = Dendro.analyze(proj; libraries = [lib])
        @test isempty(Fixtures.of_metric(findings, :library_near_duplicate))
        @test isempty(Fixtures.of_metric(findings, :library_duplicate))
    end
end

@testitem "[rules] toggles each cross-corpus pass on its own" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 9)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )
        write(
            joinpath(dir, "proj", ".dendro.toml"), """
            [rules]
            library_near_duplicate = false
            """
        )

        cfg = Fixtures.isolated_config([proj], joinpath(dir, "proj", ".dendro.toml"))
        findings = Dendro.analyze(proj; config = cfg, libraries = [lib])
        @test isempty(Fixtures.of_metric(findings, :library_near_duplicate))
    end
end

@testitem "--library indexes a reference corpus and can name it" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        proj, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )

        report = mktemp() do path, io
            rc = redirect_stdout(io) do
                Dendro.main(["--check", "--library=IterTools=$lib", proj])
            end
            # A public whole-unit match at full coverage is a `:high` finding, so the
            # gate fails on it.
            @test rc == 1
            flush(io)
            read(path, String)
        end
        @test occursin("library_duplicate 100 (high)", report)
        @test occursin("IterTools.partition public", report)

        # Named by the rule, from the root's parent when the root is a source directory.
        named = mktemp() do path, io
            redirect_stdout(io) do
                Dendro.main(["--check", "--library=$lib", proj])
            end
            flush(io)
            read(path, String)
        end
        @test occursin("dep.partition public", named)
    end
end

@testitem "a --library path that does not exist is a usage error" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        src = joinpath(dir, "src")
        mkpath(src)
        write(joinpath(src, "util.jl"), Fixtures.chain("chunk_by", 6))

        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                # A library resolving to nothing turns the gate off and reports a clean
                # run, which is the one failure this feature must not have.
                @test Dendro.main(["--library=$(joinpath(dir, "gone"))", src]) == 1
            end
        end
    end
end

@testitem "the reference cache honours DENDRO_CACHE_DIR" tags = [:libraries] begin
    mktempdir() do cache
        withenv("DENDRO_CACHE_DIR" => cache) do
            @test Dendro.reference_cache_dir() == cache
        end
    end
end

@testitem "the reference cache defaults to a Dendro scratch space" tags = [:libraries] begin
    # The suite points `DENDRO_CACHE_DIR` at a throwaway directory, so this is the one item
    # that has to look past it to see where a real run would write.
    withenv("DENDRO_CACHE_DIR" => nothing) do
        dir = Dendro.reference_cache_dir()
        @test isdir(dir)
        @test basename(dir) == "references"
        @test occursin("scratchspaces", dir)
    end
end

@testitem "a reference index is cached and reused until the library changes" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                entries() = Fixtures.cache_entries(cache)

                first_pass = Dendro.reference_index(library; min_size = 10)
                @test length(entries()) == 1
                # A second read of an unchanged library comes back byte-identical off disk.
                second = Dendro.reference_index(library; min_size = 10)
                @test length(entries()) == 1
                @test [a.hash for a in second.anchors] == [a.hash for a in first_pass.anchors]

                # A different clone floor indexes different anchors, so it keys differently.
                Dendro.reference_index(library; min_size = 4)
                @test length(entries()) == 2

                # Editing the library changes a file's size and mtime, so the key moves and
                # the stale entry is never served.
                write(joinpath(lib, "Dep.jl"), Fixtures.libmod(["partition"], Fixtures.chain("partition", 7)))
                edited = Dendro.reference_index(library; min_size = 10)
                @test length(entries()) == 3
                @test [a.hash for a in edited.anchors] != [a.hash for a in first_pass.anchors]
            end
        end
    end
end

@testitem "an unreadable cache entry is a miss, never an error" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                built = Dendro.reference_index(library; min_size = 10)
                # A cache is an optimisation and must not be able to break a scan, whatever
                # a stale format, a truncated write, or another tool left behind.
                for e in Fixtures.cache_entries(cache)
                    write(joinpath(cache, e), "not a serialized index")
                end
                again = Dendro.reference_index(library; min_size = 10)
                @test [a.hash for a in again.anchors] == [a.hash for a in built.anchors]
            end
        end
    end
end

@testitem "an untouched reference cache entry is collected" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                Dendro.reference_index(library; min_size = 10)
                @test length(Fixtures.cache_entries(cache)) == 1
                # A cutoff every entry is past, so the sweep collects the lot. The stamp is
                # what records that a sweep happened, so it survives its own pass.
                Dendro.sweep_references(cache; max_age = -1, interval = -1)
                @test isempty(Fixtures.cache_entries(cache))
                @test isfile(joinpath(cache, Dendro.REFERENCE_SWEEP_STAMP))
            end
        end
    end
end

@testitem "a fresh reference cache entry survives collection" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                Dendro.reference_index(library; min_size = 10)
                Dendro.sweep_references(cache; interval = -1)
                @test length(Fixtures.cache_entries(cache)) == 1
            end
        end
    end
end

@testitem "the reference cache sweep runs at most once per interval" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do cache
        # A sweep has just run, so the stamp is fresh.
        Dendro.sweep_references(cache; max_age = -1, interval = -1)
        # An entry every cutoff is past, written after that sweep. The next call is inside
        # the interval, so it must decline to look at all rather than collect it.
        stale = joinpath(cache, "0123456789abcdef")
        write(stale, "an index")
        Dendro.sweep_references(cache; max_age = -1)
        @test isfile(stale)
    end
end

@testitem "a reference cache hit records the entry as used" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        library = Dendro.Library("Dep", lib)

        mktempdir() do cache
            withenv("DENDRO_CACHE_DIR" => cache) do
                Dendro.reference_index(library; min_size = 10)
                entry = joinpath(cache, only(Fixtures.cache_entries(cache)))
                written = mtime(entry)
                # The sweep reads time since last use, so serving an entry has to record
                # that it was used. Without this a cache warm for months still expires.
                sleep(0.02)
                Dendro.reference_index(library; min_size = 10)
                @test mtime(entry) > written
            end
        end
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
