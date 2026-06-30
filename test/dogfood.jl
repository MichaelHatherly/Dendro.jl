# Run Dendro on its own source so complexity cannot regress unnoticed. Analyzing
# the whole directory as one corpus also exercises cross-file duplicate detection.
# The gate is `errors`: the deterministic floor of `:high`-band findings (high-band
# scalars and all flags), with inline `dendro-ignore` directives applied first. It is
# percentile-free, so the result does not depend on the corpus distribution.
@testitem "dogfood: Dendro's own source" tags = [:dogfood] begin
    using Dendro

    srcdir = joinpath(pkgdir(Dendro), "src")
    @test !isempty(filter(f -> endswith(f, ".jl"), readdir(srcdir)))

    @test isempty(Dendro.errors(srcdir))
end
