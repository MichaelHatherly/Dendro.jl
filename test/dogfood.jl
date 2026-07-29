# Run Dendro on its own source so complexity cannot regress unnoticed. Analyzing
# the whole directory as one corpus also exercises cross-file duplicate detection.
# The gate is `errors`: the deterministic floor of `:high`-band findings (high-band
# scalars and all flags), with inline `dendro-ignore` directives applied first. It is
# percentile-free, so the result does not depend on the corpus distribution.
@testitem "dogfood: Dendro's own source" tags = [:dogfood] begin
    using Dendro

    srcdir = joinpath(pkgdir(Dendro), "src")
    @test !isempty(filter(f -> endswith(f, ".jl"), readdir(srcdir)))

    errs = Dendro.errors(srcdir)
    isempty(errs) || show(stdout, MIME"text/plain"(), errs)
    @test isempty(errs)
end

# Dendro's own pattern rules, checked against their fixtures. A rule format with no test
# story would sit badly beside a package that gates itself on its own metrics, so the
# package's rules answer to the same standard a project's would.
@testitem "dogfood: Dendro's own pattern rules" tags = [:dogfood] begin
    using Dendro

    srcdir = joinpath(pkgdir(Dendro), "src")
    failures = Dendro.check_patterns(srcdir)
    isempty(failures) || foreach(f -> println(stdout, f), failures)
    @test isempty(failures)

    # A declared rule that matches nothing across the package's own source would be a
    # rule nobody has exercised.
    @test isempty(Dendro.analyze(srcdir).unmatched)
end
