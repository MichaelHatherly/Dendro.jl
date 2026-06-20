# Run Dendro on its own source so complexity cannot regress unnoticed. Analyzing
# the whole directory as one corpus also exercises cross-file duplicate detection.
# The assertions check absolute `:high` bands, presence flags, and duplicate
# clusters, none of which depend on the corpus distribution, so the result is
# deterministic.
@testitem "dogfood: Dendro's own source" tags = [:dogfood] begin
    using Dendro: analyze, active

    srcdir = joinpath(pkgdir(Dendro), "src")
    @test !isempty(filter(f -> endswith(f, ".jl"), readdir(srcdir)))

    findings = active(analyze(srcdir))

    # No genuine complexity smell, no function so structurally surprising it trips the
    # absolute naturalness floor, no file split into enough disconnected concerns to trip
    # the absolute cohesion band, and no unit coupled enough to another file to trip the
    # absolute misplacement band. `:unnatural`, `:low_cohesion`, and `:misplaced` are
    # checked on their absolute band only; their percentile flags the top of any
    # distribution and so is not part of this deterministic gate.
    smells = filter(findings) do f
        f.absolute == :high && f.metric in (:cyclomatic, :cognitive_complexity, :nesting_depth, :function_length, :boolean_complexity, :unnatural, :low_cohesion, :misplaced)
    end
    @test isempty(smells)

    # Keep our own house clean: no stubs, swallowed errors, duplicated functions
    # (exact or near), or returns that discard errors from a finally clause.
    flags = filter(findings) do f
        f.metric in (:stub_marker, :empty_catch, :empty_body, :duplicate, :near_duplicate, :return_in_finally, :identical_operands, :duplicate_branches)
    end
    @test isempty(flags)
end
