# Run Dendro on its own source so complexity cannot regress unnoticed. Analyzing
# the whole directory as one corpus also exercises cross-file duplicate detection.
# The assertions check absolute `:high` bands, presence flags, and duplicate
# clusters, none of which depend on the corpus distribution, so the result is
# deterministic.
@testset "dogfood: Dendro's own source" begin
    srcdir = joinpath(pkgdir(Dendro), "src")
    @test !isempty(filter(f -> endswith(f, ".jl"), readdir(srcdir)))

    findings = active(analyze(srcdir))

    # No genuine complexity smell. parameter_count is excluded: the
    # LanguageProfile keyword constructor takes one argument per field by design.
    smells = filter(findings) do f
        f.absolute == :high && f.metric in (:cyclomatic, :cognitive_complexity, :nesting_depth, :function_length, :boolean_complexity)
    end
    @test isempty(smells)

    # Keep our own house clean: no stubs, swallowed errors, duplicated functions
    # (exact or near), or returns that discard errors from a finally clause.
    flags = filter(findings) do f
        f.metric in (:stub_marker, :empty_catch, :empty_body, :duplicate, :near_duplicate, :return_in_finally, :identical_operands, :duplicate_branches)
    end
    @test isempty(flags)
end
