@testitem "clone_similarity is order-aware and asymmetric" tags = [:clones] begin
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 3, 4]) == 1.0
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[7, 8]) == 0.0
    # Empty inputs never arise above the size gate; guard against a NaN anyway.
    @test Dendro.clone_similarity(UInt64[], UInt64[]) == 0.0
    # A gap (one inserted node) costs proportionally: LCS 4 of the longer length 5.
    @test Dendro.clone_similarity(UInt64[1, 2, 3, 4], UInt64[1, 2, 9, 3, 4]) == 0.8
    # Order matters: a reversal shares only one element in sequence, where an
    # order-blind multiset overlap would score these identical.
    @test Dendro.clone_similarity(UInt64[1, 2, 3], UInt64[3, 2, 1]) == 1 / 3
    # A short fragment inside a long one scores low against the longer length, so the
    # verdict rejects it where a multiset overlap would not.
    @test Dendro.clone_similarity(UInt64[1, 2], UInt64[1, 2, 9, 9, 9, 9, 9, 9, 9, 9]) == 0.2
end

@testitem "clone_similarity scores near-misses below identity" setup = [Fixtures] tags = [:clones] begin
    base = "function f(x)\n    y = x + 1\n    z = y * 2\n    return z\nend\n"
    near = "function g(t)\n    a = t + 9\n    b = a * 7\n    c = b - 1\n    return c\nend\n"
    ib, inr = Fixtures.idx(:julia, base), Fixtures.idx(:julia, near)
    sf = first(Dendro.clone_features(only(Dendro.functions(ib)), ib))
    sg = first(Dendro.clone_features(only(Dendro.functions(inr)), inr))
    # `near` adds one statement, so its sequence extends `base`'s: similar, not identical.
    @test 0.5 < Dendro.clone_similarity(sf, sg) < 1.0
end

@testitem "analyze clusters near-misses across files" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        a = joinpath(dir, "a.jl")
        b = joinpath(dir, "b.jl")
        write(a, Fixtures.chain("f", 11))
        write(b, Fixtures.chain("g", 12))

        hit = only(Fixtures.near_duplicates(analyze(dir)))
        @test hit.metric == :near_duplicate
        @test hit.kind == :flag
        @test length(hit.locations) == 2
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
        @test sort([loc.file for loc in hit.locations]) == sort([a, b])
        # The value is the weakest pairwise Dice as a percent, above the cutoff.
        @test 85 <= hit.value < 100
    end
end

@testitem "exact clones are reported as duplicate, not near_duplicate" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 5))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 5))

        findings = analyze(dir)
        @test any(f -> f.metric == :duplicate, findings)
        @test isempty(Fixtures.near_duplicates(findings))
    end
end

@testitem "analyze does not cluster dissimilar functions" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 5))
        write(
            joinpath(dir, "b.jl"),
            "function g(x)\n    while x > 0\n        x -= 1\n        x *= 2\n        x += 3\n    end\n    return x\nend\n"
        )

        @test isempty(Fixtures.near_duplicates(analyze(dir)))
    end
end

@testitem "analyze finds near-misses across a size-band boundary" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # 58 named nodes (band 5) and 65 (band 6) straddle the power-of-two boundary;
        # the prefilter queries each band against the next so the pair is still seen.
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 7))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 8))

        @test length(Fixtures.near_duplicates(analyze(dir))) == 1
    end
end

@testitem "analyze detects near-misses within one file" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        file = joinpath(dir, "a.jl")
        write(file, string(Fixtures.chain("f", 11), Fixtures.chain("g", 12)))

        hit = only(Fixtures.near_duplicates(analyze(file)))
        @test all(loc.file == file for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testitem "analyze does not cluster near-misses across languages" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string(Fixtures.chain("f", 11), Fixtures.chain("g", 12)))
        write(joinpath(dir, "a.py"), string(Fixtures.pychain("f", 11), Fixtures.pychain("g", 12)))

        findings = Fixtures.near_duplicates(analyze(dir))
        @test length(findings) == 2
        for f in findings
            @test length(Set(last(splitext(loc.file)) for loc in f.locations)) == 1
        end
    end
end

@testitem "threshold gates near-misses" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 11))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 12))

        @test length(Fixtures.near_duplicates(analyze(dir))) == 1
        @test isempty(Fixtures.near_duplicates(analyze(dir; threshold = 0.95)))
    end
end

@testitem "analyze respects dendro-ignore: near_duplicate" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze, active

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), string("# dendro-ignore: near_duplicate\n", Fixtures.chain("f", 11)))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 12))

        findings = analyze(dir)
        @test any(f -> f.metric == :near_duplicate && f.suppressed, findings)
        @test isempty(Fixtures.near_duplicates(active(findings)))
    end
end

@testitem "trivial one-line functions of the same shape are not duplicates" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # Two unrelated symbol-coercion stubs, 10 named nodes each, control-free. The
        # shape coincides across unrelated code, so it anchors at the block floor.
        write(joinpath(dir, "a.jl"), "_normalize_syms(x::Symbol) = [x]\n")
        write(joinpath(dir, "b.jl"), "_flatten_cols(c::Symbol) = [c]\n")

        findings = analyze(dir)
        @test isempty(Fixtures.duplicates(findings))
        @test isempty(Fixtures.near_duplicates(findings))
    end
end

@testitem "trivial comprehension wrappers are not duplicates" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # A comprehension's `for` is a `for_clause`, not a loop, so these score
        # cyclomatic 1 at 16 named nodes: a shape, not logic.
        write(joinpath(dir, "a.jl"), "_as_pairs(v) = [_as_pair(p) for p in v]\n")
        write(joinpath(dir, "b.jl"), "_truthy_vec(col) = [_truthy_one(v) for v in col]\n")

        @test isempty(Fixtures.duplicates(analyze(dir)))
    end
end

@testitem "a control-free function above the block floor still duplicates" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # 23 named nodes each, control-free, so triviality applies but the size clears
        # the block floor. Triviality raises a floor; it never exempts.
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 2))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 2))

        hit = only(Fixtures.duplicates(analyze(dir)))
        @test Set(loc.unit for loc in hit.locations) == Set(["f", "g"])
    end
end

@testitem "a small control-bearing function still duplicates" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # 16 named nodes each, the same size band as the comprehension pair, but the
        # ternary makes them cyclomatic 2. Size is held fixed so the predicate decides.
        write(joinpath(dir, "a.jl"), "guard_a(v) = v > 0 ? v : zero(v)\n")
        write(joinpath(dir, "b.jl"), "guard_b(w) = w > 0 ? w : zero(w)\n")

        hit = only(Fixtures.duplicates(analyze(dir)))
        @test Set(loc.unit for loc in hit.locations) == Set(["guard_a", "guard_b"])
    end
end

@testitem "a duplicated block inside different functions still anchors" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # The `if` body is 29 named nodes and identical in both; everything around it
        # differs. The block floor did not move, so the shared block still anchors.
        body = "    if t > 0\n        t = t + 1\n        t = t * 2\n        t = t - 3\n        t = t + 4\n    end\n"
        write(joinpath(dir, "a.jl"), "function alpha(a)\n    t = a\n$(body)    return t\nend\n")
        write(joinpath(dir, "b.jl"), "function beta(b, c, d)\n    t = b * c * d\n$(body)    q = t - b\n    return q\nend\n")

        hit = only(Fixtures.duplicates(analyze(dir)))
        @test length(hit.locations) == 2
        # Line 4 is the first statement of the shared block, not the enclosing function.
        @test all(loc.line == 4 for loc in hit.locations)
        @test Set(loc.unit for loc in hit.locations) == Set(["alpha", "beta"])
    end
end

@testitem "unit_floor raises the floor for a control-free function" setup = [Fixtures] tags = [:clones] begin
    trivial = Fixtures.idx(:julia, "_normalize_syms(x::Symbol) = [x]\n")
    @test Dendro.unit_floor(only(Dendro.functions(trivial)).node, trivial, 10) == 20

    control = Fixtures.idx(:julia, "guard_a(v) = v > 0 ? v : zero(v)\n")
    @test Dendro.unit_floor(only(Dendro.functions(control)).node, control, 10) == 10
end

@testitem "trivial python methods of the same shape are not duplicates" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # 18 named nodes each, control-free. Python's function shape differs from
        # Julia's, so the predicate is exercised on a second grammar.
        write(joinpath(dir, "a.py"), "class A:\n    def __repr__(self):\n        return \"A(%r, %r)\" % (self.x, self.y)\n")
        write(joinpath(dir, "b.py"), "class B:\n    def __repr__(self):\n        return \"B(%r, %r)\" % (self.u, self.v)\n")

        @test isempty(Fixtures.duplicates(analyze(dir)))
    end
end

@testitem "clone clusters rank by module distance" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        # Two directories referencing nothing of each other's, so the module graph leaves
        # each its own community. The pair duplicated across them spans that boundary; the
        # triple sits inside one file.
        mkpath(joinpath(dir, "a"))
        mkpath(joinpath(dir, "b"))
        write(joinpath(dir, "a", "x.jl"), Fixtures.chain("p", 6))
        write(joinpath(dir, "b", "y.jl"), Fixtures.chain("q", 6))
        write(
            joinpath(dir, "a", "z.jl"),
            Fixtures.chain("r", 11) * Fixtures.chain("s", 11) * Fixtures.chain("t", 11)
        )

        dups = Fixtures.duplicates(analyze(dir))
        @test length(dups) == 2
        # The cross-community pair leads the larger same-file cluster: cluster size still
        # breaks ties inside one distance, but distance decides between them.
        @test Set(loc.unit for loc in first(dups).locations) == Set(["p", "q"])
        @test length(last(dups).locations) == 3
    end
end

@testitem "the clone re-rank leaves the error floor unchanged" setup = [Fixtures] tags = [:clones] begin
    using Dendro

    # A clone finding keyed the way the gate ratchet keys it, `fkey`'s (metric, sorted
    # location set) with the two fields the re-rank must never touch carried alongside.
    floorkey(f) = (f.metric, sort([(loc.file, loc.unit) for loc in f.locations]), f.value, f.absolute)
    clonekeys(fs) = sort([floorkey(f) for f in fs if f.metric in (:duplicate, :near_duplicate)])
    # The clone findings before `analyze` re-ranks them: the pass output itself, run under
    # the same resolved config both sides use, so a `.dendro.toml` retuning a clone
    # threshold moves both or neither and can never split them silently.
    function unranked(dir, cfg)
        profiles = Dendro.resolve_profiles(cfg)
        corpus = Dendro.collect_corpus([dir], String[], nothing; profiles)
        files = Dendro.parse_corpus(corpus; rules = Dendro.resolve_rules(cfg), profiles)
        return [
            Dendro.cluster_duplicates(files; min_size = cfg.min_size);
            Dendro.cluster_near_duplicates(
                files; min_size = cfg.min_size, threshold = cfg.threshold,
                radius_factor = cfg.radius_factor
            )
        ]
    end
    floor_of(dir, cfg) = clonekeys(filter(f -> !f.suppressed, unranked(dir, cfg)))

    mktempdir() do dir
        mkpath(joinpath(dir, "a"))
        mkpath(joinpath(dir, "b"))
        write(joinpath(dir, "a", "x.jl"), Fixtures.chain("p", 6))
        write(joinpath(dir, "b", "y.jl"), Fixtures.chain("q", 6))
        write(joinpath(dir, "b", "w.jl"), Fixtures.chain("u", 7))
        write(joinpath(dir, "a", "z.jl"), Fixtures.chain("r", 11) * Fixtures.chain("s", 11))

        cfg = Dendro.discover_config([dir])
        before = floor_of(dir, cfg)
        # The corpus is built to clone, so an equality between two empty sets is no proof.
        @test !isempty(before)
        @test clonekeys(Dendro.errors(dir; config = cfg)) == before
    end

    # Dendro's own source, the corpus the dogfood floor gates on.
    srcdir = joinpath(pkgdir(Dendro), "src")
    srccfg = Dendro.discover_config([srcdir])
    @test clonekeys(Dendro.errors(srcdir; config = srccfg)) == floor_of(srcdir, srccfg)
end

@testitem "clone findings are emitted at the high band" setup = [Fixtures] tags = [:clones] begin
    using Dendro: analyze

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), Fixtures.chain("f", 11))
        write(joinpath(dir, "b.jl"), Fixtures.chain("g", 11))
        write(joinpath(dir, "c.jl"), Fixtures.chain("h", 12))

        findings = analyze(dir)
        # `:high` is what puts a clone inside the floor `errors` gates on, so a package
        # downstream gating its own tests on Dendro depends on this literal. The re-rank
        # compares two sides of one run and would not notice the band moving under both.
        dup = only(Fixtures.duplicates(findings))
        @test dup.absolute === :high
        @test dup.value == 2
        near = only(Fixtures.near_duplicates(findings))
        @test near.absolute === :high
        @test 85 <= near.value < 100
    end
end

@testitem "the re-rank orders reimplementation pairs without rescoring them" setup = [Fixtures] tags = [:clones, :reimpl] begin
    using Dendro: analyze, discover_config

    # Two vocabulary families, each written twice: once straight-line, once around a loop,
    # so no structural pass claims either pair. The first family is split across two
    # directories that reference nothing of each other's, the second sits in one file.
    mktempdir() do dir
        mkpath(joinpath(dir, "net"))
        mkpath(joinpath(dir, "web"))
        write(
            joinpath(dir, "net", "a.jl"),
            """
            function fetch_once(url)
                delay = backoff_delay(url)
                jitter = compute_jitter(delay)
                response = http_get(url, delay + jitter)
                check_status(response)
                return response
            end
            """
        )
        write(
            joinpath(dir, "web", "b.jl"),
            """
            function fetch_retrying(url)
                for attempt in 1:3
                    delay = backoff_delay(url)
                    jitter = compute_jitter(delay)
                    response = http_get(url, delay + jitter)
                    if check_status(response)
                        return response
                    end
                end
                return nothing
            end
            """
        )
        write(
            joinpath(dir, "net", "c.jl"),
            """
            function encode_frame(frame)
                header = frame_header(frame)
                checksum = frame_checksum(header)
                trailer = frame_trailer(checksum)
                payload = frame_payload(frame, checksum)
                emit_frame(header, payload, trailer)
                return payload
            end

            function encode_frame_stream(frames)
                for frame in frames
                    header = frame_header(frame)
                    checksum = frame_checksum(header)
                    trailer = frame_trailer(checksum)
                    payload = frame_payload(frame, checksum)
                    if emit_frame(header, payload, trailer)
                        return payload
                    end
                end
                return nothing
            end
            """
        )
        write(
            joinpath(dir, "web", "d.jl"),
            """
            function sum_lengths(items)
                total = 0
                for item in items
                    total += length(item)
                end
                return total
            end
            """
        )

        mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                cfg = discover_config([dir]; use_files = false)
                cfg.rules[:reimplementation] = true

                profiles = Dendro.resolve_profiles(cfg)
                corpus = Dendro.collect_corpus([dir], String[], nothing; profiles)
                files = Dendro.parse_corpus(corpus; rules = Dendro.resolve_rules(cfg), profiles)
                clones = [
                    Dendro.cluster_duplicates(files; min_size = cfg.min_size);
                    Dendro.cluster_near_duplicates(files; min_size = cfg.min_size)
                ]
                before = Dendro.cluster_reimplementations(
                    files; min_size = cfg.min_size, threshold = cfg.reimpl_threshold,
                    clone_findings = clones
                )
                units(f) = Set(loc.unit for loc in f.locations)
                scores = Dict(units(f) => (f.value, f.absolute) for f in before)
                @test length(scores) == 2

                after = filter(f -> f.metric === :reimplementation, analyze(dir; config = cfg))
                @test length(after) == 2
                # Split across two communities, so it leads the pair sharing one file.
                @test units(first(after)) == Set(["fetch_once", "fetch_retrying"])
                @test units(last(after)) == Set(["encode_frame", "encode_frame_stream"])
                # Ranked, not rescored: the overlap percent and the band come through as
                # the pass wrote them.
                @test all(scores[units(f)] == (f.value, f.absolute) for f in after)
                @test all(f.absolute === :high for f in after)
            end
        end
    end
end
