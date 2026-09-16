# The corpus summary scores. Erosion and verbosity are ratios over a whole corpus, so
# every item here asserts the arithmetic against hand-computed numbers rather than
# against a band: a score names no site and so has no threshold to test.

# Two callables, one over the CC>10 cut and one under it. The numerator is the heavy
# unit's mass alone, the denominator both, so the expected value is written out rather
# than recomputed from the same code under test.
@testitem "erosion is the mass share of the complex callables" tags = [:summary] setup = [Fixtures] begin
    hot = """
    function hot(x)
        x > 1 && return 1
        x > 2 && return 2
        x > 3 && return 3
        x > 4 && return 4
        x > 5 && return 5
        x > 6 && return 6
        x > 7 && return 7
        x > 8 && return 8
        x > 9 && return 9
        x > 10 && return 10
        x > 11 && return 11
        return 0
    end
    """
    cold = """
    function cold(x)
        x > 1 && return 1
        return 0
    end
    """
    files = [
        Fixtures.parsedfile(:julia, hot; file = "hot.jl"),
        Fixtures.parsedfile(:julia, cold; file = "cold.jl"),
    ]
    # Pin the inputs the arithmetic reads, so a change in either metric fails here
    # naming the metric rather than the ratio.
    hotunit = only(Dendro.units(files[1].index))
    coldunit = only(Dendro.units(files[2].index))
    @test Dendro.cyclomatic(hotunit, files[1].index) == 12
    @test Dendro.function_length(hotunit) == 14
    @test Dendro.cyclomatic(coldunit, files[2].index) == 2
    @test Dendro.function_length(coldunit) == 4

    # mass(hot) = 12 * sqrt(14), mass(cold) = 2 * sqrt(4) = 4; only hot clears CC > 10.
    expected = 12 * sqrt(14) / (12 * sqrt(14) + 4)
    scores = Dendro.corpus_scores(files, Dendro.Finding[], Dendro.PatternSpec[])
    @test scores.erosion ≈ expected atol = 1.0e-9
    @test scores.callables == 2
end

# A corpus of top-level code alone has no mass to divide, and the ratio has to be zero
# rather than a NaN a report would print.
@testitem "erosion is zero with no callables" tags = [:summary] setup = [Fixtures] begin
    files = [Fixtures.parsedfile(:julia, "x = 1\ny = 2\n"; file = "top.jl")]
    scores = Dendro.corpus_scores(files, Dendro.Finding[], Dendro.PatternSpec[])
    @test scores.callables == 0
    @test scores.erosion == 0.0
end

@testitem "verbosity is the share of lines a declared flag covers" tags = [:summary] setup = [Fixtures] begin
    # Ten physical lines, of which the rule covers the three the `if` runs over.
    src = "function f(x)\n    if x > 0\n        g(x)\n    end\n    return x\nend\n" *
        "h(y) = y\ni(y) = y\nj(y) = y\nk(y) = y\n"
    files = [Fixtures.patternfile(:julia, src, "(if_statement) @three\n"; file = "f.jl")]
    spec = Dendro.PatternSpec(:three, "m", :warn, :flag, nothing)
    scores = Dendro.corpus_scores(files, Dendro.Finding[], [spec])
    @test scores.lines == 10
    @test scores.verbosity ≈ 0.3 atol = 1.0e-9
end

# Verbosity is how much of the corpus a finding implicates, not how many findings there
# are, so two readings over one region count that region once.
@testitem "a clone over a flagged region counts its lines once" tags = [:summary] setup = [Fixtures] begin
    src = "function f(x)\n    if x > 0\n        g(x)\n    end\n    return x\nend\n" *
        "h(y) = y\ni(y) = y\nj(y) = y\nk(y) = y\n"
    files = [Fixtures.patternfile(:julia, src, "(if_statement) @three\n"; file = "f.jl")]
    spec = Dendro.PatternSpec(:three, "m", :warn, :flag, nothing)

    # A clone spanning lines 2 to 4, the same region the rule already covers, plus line 5.
    clone = Dendro.Finding(
        :duplicate, [Dendro.Location("f.jl", 2, "f", "", 5)], 2, :high, nothing, :flag, false
    )
    scores = Dendro.corpus_scores(files, [clone], [spec])
    @test scores.verbosity ≈ 0.4 atol = 1.0e-9
end

# The numerator is the declared rule set. A scalar rule reads a count per unit rather than
# a region, and a built-in flag has a population of a different shape, so neither is in it.
@testitem "a scalar rule and a built-in flag stay out of verbosity" tags = [:summary] setup = [Fixtures] begin
    # The empty catch is a built-in flag, and the rule declared over the same file is a
    # scalar. Ten lines, nothing covered.
    src = "function f(x)\n    try\n        g(x)\n    catch\n    end\n    return x\nend\n" *
        "h(y) = y\ni(y) = y\nj(y) = y\n"
    files = [Fixtures.patternfile(:julia, src, "(call_expression) @calls\n"; file = "f.jl")]
    spec = Dendro.PatternSpec(:calls, "m", :warn, :scalar, (1, 2))
    scores = Dendro.corpus_scores(files, Dendro.Finding[], [spec])
    @test scores.lines == 10
    @test scores.verbosity == 0.0
end

# A diff narrows which findings get reported; it never narrows the corpus a ratio is taken
# over. Both halves of the score have their own route past the scope, and this is what
# holds them to it.
@testitem "the summary scores the whole corpus under a diff scope" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    for name in ("a.jl", "b.jl", "c.jl")
        write(joinpath(src, name), "f_$(name[1])(x) = x\n")
    end
    Fixtures.commit!(root, "init")
    write(joinpath(src, "a.jl"), "f_a(x) = x\ng_a(x) = x\n")

    whole = Dendro.analyze(src).summary.now
    scoped = Dendro.analyze(src; base = "HEAD").summary.now
    @test whole.lines == 4
    @test scoped.lines == whole.lines
    @test scoped.callables == whole.callables
end

# The gate drops the summary along with the unmatched-rule list: a ratchet compares finding
# sets, and a corpus ratio is not one. `active` keeps both, since it only filters findings.
@testitem "active keeps the summary and the gate drops it" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")

    findings = Dendro.analyze(src)
    kept = Dendro.active(findings)
    @test kept.summary.now.lines == findings.summary.now.lines
    @test kept.unmatched == findings.unmatched
    @test Dendro.errors(src).summary.now.lines == 0
end

@testitem "the text report carries the scores and annotations do not" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    findings = Dendro.analyze(src)

    text = sprint(show, MIME("text/plain"), findings)
    @test occursin("erosion", text)
    @test occursin("verbosity", text)
    # No base ref, so neither line carries a comparison.
    @test !occursin("base", text)

    annotations = sprint(Dendro.github_annotations, findings)
    @test !occursin("erosion", annotations)
    @test !occursin("verbosity", annotations)
end

# A trend needs two readings. With a base ref the same scores are taken over the corpus as
# it stood there, which is what lets the report say which way an edit moved them.
@testitem "a base ref is scored as a corpus of its own" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    Fixtures.commit!(root, "init")
    write(
        joinpath(src, "b.jl"),
        "function hot(x)\n" * join("    x > $i && return $i\n" for i in 1:11) * "    return 0\nend\n"
    )

    summary = Dendro.analyze(src; base = "HEAD").summary
    @test summary.base.lines == 1
    @test summary.base.erosion == 0.0
    @test summary.now.erosion > summary.base.erosion

    text = sprint(show, MIME("text/plain"), Dendro.analyze(src; base = "HEAD"))
    @test occursin("(base 0.00, +", text)
end

@testitem "base summary scoring can be disabled" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    Fixtures.commit!(root, "init")
    write(joinpath(src, "a.jl"), "f(x) = x\ng(x) = x\n")

    skipped = Dendro.analyze(
        src; base = "HEAD", config = Dendro.Config(; base_summary = false)
    ).summary
    @test skipped.base == Dendro.CorpusScores()
    @test skipped.now.lines == 2
    @test skipped.now.callables == 2
    @test skipped.delta == Dendro.LineDelta(1, 0)

    measured = Dendro.analyze(src; base = "HEAD").summary
    @test measured.base.lines == 1
end

# The delta counts the paths the scan would have parsed, not the paths it did: a file the
# change deleted is in no corpus, and a net count has to go negative on a deletion.
@testitem "the line delta counts the source a scan would have read" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\ng(x) = x\n")
    write(joinpath(src, "notes.md"), "one\n")
    Fixtures.commit!(root, "init")
    # Three lines in, one out, plus a markdown edit no profile claims.
    write(joinpath(src, "a.jl"), "f(x) = x\nh1(x) = x\nh2(x) = x\nh3(x) = x\n")
    write(joinpath(src, "notes.md"), "one\ntwo\nthree\n")

    @test Dendro.analyze(src; base = "HEAD").summary.delta == Dendro.LineDelta(3, 1)
end

@testitem "a deleted file's lines land in removed" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    write(joinpath(src, "gone.jl"), "g(x) = x\nh(x) = x\n")
    Fixtures.commit!(root, "init")
    rm(joinpath(src, "gone.jl"))

    @test Dendro.analyze(src; base = "HEAD").summary.delta == Dendro.LineDelta(0, 2)
end

@testitem "an ignored path contributes no lines" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    mkpath(joinpath(src, "vendor"))
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    write(joinpath(src, "vendor", "v.jl"), "v(x) = x\n")
    Fixtures.commit!(root, "init")
    write(joinpath(src, "a.jl"), "f(x) = x\nf2(x) = x\n")
    write(joinpath(src, "vendor", "v.jl"), "v(x) = x\nv2(x) = x\nv3(x) = x\n")

    delta = Dendro.analyze(src; base = "HEAD", ignore = ["vendor/"]).summary.delta
    @test delta == Dendro.LineDelta(1, 0)
end

@testitem "the delta line prints only against a base ref" tags = [:summary] setup = [Fixtures] begin
    root, src = Fixtures.gitrepo()
    write(joinpath(src, "a.jl"), "f(x) = x\n")
    Fixtures.commit!(root, "init")
    write(joinpath(src, "a.jl"), "f(x) = x\ng(x) = x\n")

    @test occursin(
        "lines     +1 -0  (net +1)",
        sprint(show, MIME("text/plain"), Dendro.analyze(src; base = "HEAD"))
    )
    @test !occursin("lines ", sprint(show, MIME("text/plain"), Dendro.analyze(src)))
    @test Dendro.errors(src).summary.delta == Dendro.LineDelta(0, 0)
end
