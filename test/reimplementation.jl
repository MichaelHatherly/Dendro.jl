@testitem "subtokens" tags = [:reimpl] begin
    st = Dendro.subtokens
    @test st("parse_header") == ["parse", "header"]
    @test st("validateEmailAddress") == ["validate", "email", "address"]
    @test st("HTTPServer") == ["http", "server"]
    @test st("parseHTTPResponse") == ["parse", "http", "response"]
    @test st("SCREAMING_CASE") == ["screaming", "case"]
    @test st("kebab-case") == ["kebab", "case"]
    @test st("__init__") == ["init"]
    @test st("base64") == ["base64"]
    @test st("x") == String[]
    @test st("a_1") == String[]
    @test st("") == String[]
end

@testitem "callees_by_unit matches fan_out" setup = [Fixtures] tags = [:reimpl] begin
    src = """
    function outer(x)
        a = parse_header(x)
        b = validate(a)
        function inner()
            return render(b)
        end
        return inner
    end
    """
    index = Fixtures.idx(:julia, src)
    units = Dendro.functions(index)
    sets = Dendro.callees_by_unit(index)
    @test length(sets) == length(units)
    for (i, u) in enumerate(units)
        @test Dendro.fan_out(u, index) == length(sets[i])
    end
    # The closure's call belongs to the closure, not the enclosing function.
    outer = findfirst(s -> "parse_header" in s, sets)
    @test !("render" in sets[outer])
    @test any(s -> s == Set(["render"]), sets)
end

@testitem "reimpl_units fingerprints" setup = [Fixtures] tags = [:reimpl] begin
    src = """
    function fetch_with_backoff(url)
        delay = backoff_delay(url)
        return http_get(url, delay)
    end
    """
    f = Fixtures.parsedfile(:julia, src)
    units = Dendro.reimpl_units([f], 1)
    u = only(units)
    @test u.name == "fetch_with_backoff"
    @test u.callees == Set(["backoff_delay", "http_get"])
    # Callee full names are namespaced apart from identifier subtokens.
    @test "c:backoff_delay" in u.terms
    @test "c:http_get" in u.terms
    # Identifier subtokens, including the unit's own name.
    @test "fetch" in u.terms
    @test "backoff" in u.terms
    @test "delay" in u.terms
    @test "url" in u.terms
    # Never un-namespaced whole callee entries beyond their subtokens.
    @test !("http_get" in u.terms)
end

@testitem "reimpl_units floor and suppression" setup = [Fixtures] tags = [:reimpl] begin
    src = "function f(x)\n    g(x)\nend\n"
    f = Fixtures.parsedfile(:julia, src)
    @test isempty(Dendro.reimpl_units([f], 100))

    dirs = [Dendro.Directive(1, Set([:reimplementation]))]
    f = Fixtures.parsedfile(:julia, src; directives = dirs)
    @test only(Dendro.reimpl_units([f], 1)).suppressed
end

@testitem "reimpl_units nested callable attribution" setup = [Fixtures] tags = [:reimpl] begin
    src = """
    function outer(x)
        function inner()
            return zebra_token(x)
        end
        return inner
    end
    """
    f = Fixtures.parsedfile(:julia, src)
    units = Dendro.reimpl_units([f], 1)
    outer = only(filter(u -> u.name == "outer", units))
    @test !("zebra" in outer.terms)
    @test any(u -> u.name != "outer" && "zebra" in u.terms, units)
end

@testitem "term_stats idf and rarity" tags = [:reimpl] begin
    unit(terms) = Dendro.ReimplUnit(
        :julia, Dendro.Location("f.jl", 1, "u"), false, "u",
        Set{String}(), Set{String}(terms), UInt64(0), 10
    )
    units = [unit(["shared", "a"]), unit(["shared", "b"]), unit(["shared", "c"])]
    idf, rare = Dendro.term_stats(units, [1, 2, 3])
    # N = 3: idf(t) = log2(4 / (df + 1)).
    @test idf["shared"] == log2(4 / 4)
    @test idf["a"] == log2(4 / 2)
    # Cap is max(2, cld(3, 50)) = 2: a hapax is not pairable, a term in
    # every unit is not rare.
    @test isempty(rare)

    units = [unit(["dup", "x"]), unit(["dup", "y"]), unit(["z"])]
    _, rare = Dendro.term_stats(units, [1, 2, 3])
    @test rare == Set(["dup"])
end

@testitem "reimpl_candidates inverted index" tags = [:reimpl] begin
    unit(terms) = Dendro.ReimplUnit(
        :julia, Dendro.Location("f.jl", 1, "u"), false, "u",
        Set{String}(), Set{String}(terms), UInt64(0), 10
    )
    # Units 1 and 2 share two rare terms; unit 3 shares only one with each.
    units = [unit(["r1", "r2", "x"]), unit(["r1", "r2", "y"]), unit(["r1", "z"])]
    rare = Set(["r1", "r2"])
    @test Dendro.reimpl_candidates(units, [1, 2, 3], rare) == [(1, 2)]

    # A term outside the rare set proposes nothing.
    @test isempty(Dendro.reimpl_candidates(units, [1, 2, 3], Set(["x", "y", "z"])))

    # Deterministic: same input, same order.
    units = [unit(["r1", "r2"]), unit(["r1", "r2"]), unit(["r1", "r2"])]
    pairs = Dendro.reimpl_candidates(units, [1, 2, 3], Set(["r1", "r2"]))
    @test pairs == [(1, 2), (1, 3), (2, 3)]
end

@testitem "reimpl_score weighted jaccard" tags = [:reimpl] begin
    unit(terms) = Dendro.ReimplUnit(
        :julia, Dendro.Location("f.jl", 1, "u"), false, "u",
        Set{String}(), Set{String}(terms), UInt64(0), 10
    )
    idf = Dict("x" => 1.0, "y" => 2.0, "z" => 3.0)
    a = unit(["x", "y"])
    b = unit(["y", "z"])
    @test Dendro.reimpl_score(a, b, idf) ≈ 2.0 / 6.0
    @test Dendro.reimpl_score(a, b, idf) == Dendro.reimpl_score(b, a, idf)
    @test Dendro.reimpl_score(a, a, idf) ≈ 1.0

    empty = unit(String[])
    @test Dendro.reimpl_score(empty, empty, idf) == 0.0
end

@testitem "cluster_reimplementations flags vocabulary twins" setup = [Fixtures] tags = [:reimpl] begin
    # Same rare vocabulary (backoff/jitter/http), different structure: the
    # straight-line version against the loop version. Not structural clones.
    a = Fixtures.parsedfile(
        :julia,
        """
        function fetch_once(url)
            delay = backoff_delay(url)
            jitter = compute_jitter(delay)
            response = http_get(url, delay + jitter)
            check_status(response)
            return response
        end
        """; file = "a.jl"
    )
    b = Fixtures.parsedfile(
        :julia,
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
        """; file = "b.jl"
    )
    background = Fixtures.parsedfile(
        :julia,
        """
        function sum_lengths(items)
            total = 0
            for item in items
                total += length(item)
            end
            return total
        end
        """; file = "c.jl"
    )
    files = [a, b, background]
    findings = Dendro.cluster_reimplementations(files; min_size = 5, threshold = 0.3)
    f = only(findings)
    @test f.metric == :reimplementation
    @test f.kind == :flag
    @test f.absolute == :high
    @test f.percentile === nothing
    @test length(f.locations) == 2
    @test Set(l.unit for l in f.locations) == Set(["fetch_once", "fetch_retrying"])
    @test Set(l.file for l in f.locations) == Set(["a.jl", "b.jl"])
    @test 1 <= f.value <= 100
    @test !f.suppressed
end

@testitem "cluster_reimplementations gates" setup = [Fixtures] tags = [:reimpl] begin
    # A third unit keeps the corpus big enough that shared terms stay rare:
    # with two units a shared term is in every unit and its IDF is zero, so a
    # gate test without it passes vacuously.
    background = Fixtures.parsedfile(
        :julia,
        """
        function sum_lengths(items)
            total = 0
            for item in items
                total += length(item)
            end
            return total
        end
        """; file = "c.jl"
    )

    # Caller/callee: shares vocabulary because it calls the original. Skipped.
    caller = Fixtures.parsedfile(
        :julia,
        """
        function fetch_wrapper(url)
            delay = backoff_delay(url)
            jitter = compute_jitter(delay)
            response = fetch_once(url, delay, jitter)
            check_status(response)
            return response
        end
        """; file = "w.jl"
    )
    callee = Fixtures.parsedfile(
        :julia,
        """
        function fetch_once(url)
            delay = backoff_delay(url)
            jitter = compute_jitter(delay)
            response = http_get(url, delay + jitter)
            check_status(response)
            return response
        end
        """; file = "o.jl"
    )
    # The pair clears the threshold once the call is renamed away, so the
    # direct-call gate is what silences it.
    files = [caller, callee, background]
    findings = Dendro.cluster_reimplementations(files; min_size = 5, threshold = 0.1)
    @test isempty(findings)

    # Same-named units never pair: overloads and interface methods share
    # vocabulary legitimately.
    other = Fixtures.parsedfile(
        :julia,
        """
        function fetch_once(url, retries)
            delay = backoff_delay(url)
            jitter = compute_jitter(delay)
            result = http_get(url, delay * jitter * retries)
            check_status(result)
            return result
        end
        """; file = "p.jl"
    )
    findings = Dendro.cluster_reimplementations([callee, other, background]; min_size = 5, threshold = 0.1)
    @test isempty(findings)

    # The same pair under different names fires, so the gates above are what
    # silenced the caller/callee and same-name cases, not a failing score.
    renamed = Fixtures.parsedfile(
        :julia,
        replace(String(other.source), "fetch_once" => "fetch_again"); file = "p.jl"
    )
    findings = Dendro.cluster_reimplementations([callee, renamed, background]; min_size = 5, threshold = 0.1)
    @test !isempty(findings)
end

@testitem "cluster_reimplementations defers to clone findings" setup = [Fixtures] tags = [:reimpl] begin
    # A near-miss clone pair (one extra statement) is the near-duplicate pass's
    # finding; the reimplementation pass stays quiet on it. Changing only a
    # callee name would not do here: Type-2 hashing drops identifier text, so
    # that pair would be an exact clone and fail this test's premise.
    src(fname, extra) = """
    function $fname(url)
        $extra
        delay = backoff_delay(url)
        jitter = compute_jitter(delay)
        response = http_get(url, delay + jitter)
        check_status(response)
        return response
    end
    """
    a = Fixtures.parsedfile(:julia, src("fetch_a", ""); file = "a.jl")
    b = Fixtures.parsedfile(:julia, src("fetch_b", "log_request(url)"); file = "b.jl")
    # A third unit keeps the pair's shared terms rare; with two units their
    # IDF is zero and both asserts below would pass vacuously.
    background = Fixtures.parsedfile(
        :julia,
        """
        function sum_lengths(items)
            total = 0
            for item in items
                total += length(item)
            end
            return total
        end
        """; file = "c.jl"
    )
    files = [a, b, background]
    clones = Dendro.cluster_near_duplicates(files; min_size = 5, threshold = 0.8)
    @test !isempty(clones)   # the pair really is a near-miss clone
    findings = Dendro.cluster_reimplementations(
        files; min_size = 5, threshold = 0.1, clone_findings = clones
    )
    @test isempty(findings)

    # Without the handoff the pair would fire, so the exclusion is load-bearing.
    findings = Dendro.cluster_reimplementations(files; min_size = 5, threshold = 0.1)
    @test !isempty(findings)
end

@testitem "analyze gates the reimplementation pass" setup = [Fixtures] tags = [:reimpl] begin
    using Dendro: analyze, discover_config

    # Vocabulary twins plus background, as files on disk for the full pipeline.
    twins(dir) = begin
        write(
            joinpath(dir, "a.jl"),
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
            joinpath(dir, "b.jl"),
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
            joinpath(dir, "c.jl"),
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
    end
    reimpl(findings) = filter(f -> f.metric === :reimplementation, findings)

    # Off by default.
    mktempdir() do dir
        twins(dir)
        mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                @test isempty(reimpl(analyze(dir)))

                # On via a passed config.
                cfg = discover_config([dir]; use_files = false)
                cfg.rules[:reimplementation] = true
                found = reimpl(analyze(dir; config = cfg))
                @test !isempty(found)
                f = first(found)
                @test f.kind === :flag
                @test length(f.locations) == 2
                @test Set(l.unit for l in f.locations) == Set(["fetch_once", "fetch_retrying"])

                # On via a repo .dendro.toml, threshold from its table.
                write(joinpath(dir, ".dendro.toml"), "[rules]\nreimplementation = true\n[reimplementation]\nthreshold = 0.2\n")
                @test !isempty(reimpl(analyze(dir)))

                # A tight threshold silences the pair.
                write(joinpath(dir, ".dendro.toml"), "[rules]\nreimplementation = true\n[reimplementation]\nthreshold = 0.99\n")
                @test isempty(reimpl(analyze(dir)))
            end
        end
    end
end

@testitem "reimplementation findings are suppressible end to end" setup = [Fixtures] tags = [:reimpl] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        write(
            joinpath(dir, "a.jl"),
            """
            # dendro-ignore: reimplementation
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
            joinpath(dir, "b.jl"),
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
        write(joinpath(dir, "c.jl"), "function sum_lengths(items)\n    total = 0\n    for item in items\n        total += length(item)\n    end\n    return total\nend\n")
        cfg = discover_config([dir]; use_files = false)
        cfg.rules[:reimplementation] = true
        findings = analyze(dir; config = cfg)
        @test any(f -> f.metric === :reimplementation && f.suppressed, findings)
        @test isempty(filter(f -> f.metric === :reimplementation, Dendro.active(findings)))
    end
end

@testitem "cluster_reimplementations suppression" setup = [Fixtures] tags = [:reimpl] begin
    src(fname) = """
    function $fname(url)
        delay = backoff_delay(url)
        jitter = compute_jitter(delay)
        response = http_get(url, delay, jitter, $(fname == "fetch_a" ? "1" : "2 + 2"))
        check_status(response)
        return response
    end
    """
    dirs = [Dendro.Directive(1, Set([:reimplementation]))]
    a = Fixtures.parsedfile(:julia, src("fetch_a"); file = "a.jl", directives = dirs)
    b = Fixtures.parsedfile(:julia, src("fetch_b"); file = "b.jl")
    background = Fixtures.parsedfile(
        :julia,
        """
        function sum_lengths(items)
            total = 0
            for item in items
                total += length(item)
            end
            return total
        end
        """; file = "c.jl"
    )
    findings = Dendro.cluster_reimplementations([a, b, background]; min_size = 5, threshold = 0.1)
    @test !isempty(findings)   # suppressed is marked, never dropped
    @test all(f -> f.suppressed, findings)
end
