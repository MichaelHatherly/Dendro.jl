# Run Dendro on its own source so complexity cannot regress unnoticed. Absolute
# bands only (no baseline), so the result is deterministic rather than dependent
# on the corpus distribution.
@testset "dogfood: Dendro's own source" begin
    srcdir = joinpath(pkgdir(Dendro), "src")
    files = filter(f -> endswith(f, ".jl"), readdir(srcdir; join = true))
    @test !isempty(files)

    findings = Finding[]
    for file in files
        append!(findings, active(analyze(file)))
    end

    # No genuine complexity smell. parameter_count is excluded: the
    # LanguageProfile keyword constructor takes one argument per field by design.
    smells = filter(findings) do f
        f.absolute == :high && f.metric in (:cyclomatic, :nesting_depth, :function_length)
    end
    @test isempty(smells)

    # Keep our own house clean: no stubs or swallowed errors.
    flags = filter(f -> f.metric in (:stub_marker, :empty_catch, :empty_body), findings)
    @test isempty(flags)
end
