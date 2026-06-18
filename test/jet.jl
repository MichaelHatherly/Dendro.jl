import JET

# JET's basic static analysis over Dendro's own modules. A type-level regression,
# a call that admits a no-method branch, fails the suite here rather than at runtime.
JET.test_package(Dendro; target_defined_modules = true, mode = :basic)

# Sound mode and the optimization analyzer flag far more, mostly intentional dynamic
# dispatch on Dendro's design (function-valued rules, tree-walks over `Any` nodes).
# Rather than gate at zero, ratchet: cap the count at its current
# value so it can only fall. Lower a limit whenever the count drops, that locks in the
# cleanup; never raise one without a reason. The counts depend on the Julia and JET
# versions (JET pinned to 0.10 in test/Project.toml), so the ratchet runs only on the
# Julia version the limits were measured against, and skips elsewhere.
const JET_JULIA = v"1.12"
const SOUND_LIMIT = 419   # JET.report_package(Dendro; mode = :sound). +1 over the metric-only baseline for the near-miss clone pass's one dynamically-typed feature call.
const OPT_LIMIT = 6       # JET.report_opt on analyze(::String), scoped to Dendro

if (VERSION.major, VERSION.minor) == (JET_JULIA.major, JET_JULIA.minor)
    @testset "JET ratchet" begin
        sound = JET.get_reports(JET.report_package(Dendro; target_defined_modules = true, mode = :sound))
        length(sound) < SOUND_LIMIT && @info "JET sound below limit; lower SOUND_LIMIT to $(length(sound))"
        @test length(sound) <= SOUND_LIMIT

        opt = JET.get_reports(JET.report_opt(Tuple{typeof(Dendro.analyze), String}; target_modules = (Dendro,)))
        length(opt) < OPT_LIMIT && @info "JET opt below limit; lower OPT_LIMIT to $(length(opt))"
        @test length(opt) <= OPT_LIMIT
    end
else
    @testset "JET ratchet (skipped, counts pinned to Julia $JET_JULIA)" begin
        @test true skip = true
    end
end
