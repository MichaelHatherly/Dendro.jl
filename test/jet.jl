# JET static analysis over Dendro's own modules. JET loads only a stub on
# pre-release Julia and errors when called, so skip the whole analysis there
# (nightly runs in CI).
#
# Basic mode is a zero-tolerance gate on every stable Julia version: a type-level
# regression, a call that admits a no-method branch, fails here rather than at
# runtime. Pkg resolves a version-appropriate JET release per Julia (0.9 on 1.11,
# 0.10 on 1.12).
#
# Sound mode and the optimization analyzer flag far more, mostly intentional dynamic
# dispatch on Dendro's design (function-valued rules, tree-walks over `Any` nodes).
# Rather than gate at zero, ratchet: cap the count at its current value so it can
# only fall. Lower a limit whenever the count drops, that locks in the cleanup;
# never raise one without a reason. The counts depend on the Julia and JET versions
# (JET 0.10 on Julia 1.12), so the ratchet runs only on that Julia version, and
# skips elsewhere. The sound count rose from 462 to 472 with the Julia 1.12.6 / JET
# 0.10.15 bump; it is identical on the prior commit, so it tracks the toolchain, not
# a code regression. The `:unreferenced` pass then raised it from 472 to 478 and the
# opt count from 12 to 13: the reachability resolver dispatches through the
# function-valued `Linkage.is_public` field, the same intentional dynamic dispatch the
# function-valued rules already incur. Java's `:package` linkage (same-package type
# resolution, the per-def visibility navigation) raised the sound count again from 478 to
# 481, more `Any`-node tree walks of the same kind. Routing visibility through the
# function-valued `Linkage.visibility` field, like the other per-language hooks, raised
# sound to 482 and opt to 14: one more dynamic dispatch of the kind already counted. The
# mermaid graph export (`mermaid.jl`) raised sound from 482 to 505, opt unchanged: a second
# public entrypoint, `mermaid`, carries `analyze`'s keyword-argument and `Vector{String}`
# paths machinery, and its three renderers walk the same `Any` nodes the corpus passes do,
# no new kind of dynamic dispatch, just a second site for it. Focus filtering (the
# `focus`/`context` keywords) raised sound from 505 to 550, opt unchanged: two more keyword
# arguments widen `mermaid`'s kwarg lowering, and the shared `neighbourhood`/`undirected`
# helpers are generic over the unit-index and file-path node ids, so sound mode analyses
# their bodies with the type variable unbound to `Any`. Specialising them would reintroduce
# the duplication the dogfood gate flags; the kinds are the ones already counted. The
# `errors` quality gate (`gate.jl`) raised sound from 550 to 601, opt unchanged: a third
# public entrypoint carrying `analyze`'s keyword-argument and `Vector{String}` paths
# machinery, and the `since` ratchet runs a second `analyze` then walks each finding's
# locations through `fkey`/`ratchet`, the same `Any`-node and function-valued dispatch
# already counted, just more sites for it. The configurable thresholds and the CLI
# (`config.jl`, `main.jl`) raised sound from 601 to 806 and opt from 14 to 19: the
# `.dendro.toml` loader walks the `Dict{String, Any}` `TOML.parsefile` returns, and
# `main`/`run_cli` re-enter `analyze`'s keyword-argument and `Vector{String}` paths
# machinery, the same `Any`-value and kwarg-lowering dispatch already counted, at new
# sites.
@testitem "JET" tags = [:jet] begin
    import JET

    if isempty(VERSION.prerelease)
        JET.test_package(Dendro; target_defined_modules = true, mode = :basic)

        JET_JULIA = v"1.12"
        SOUND_LIMIT = 806   # JET.report_package(Dendro; mode = :sound).
        OPT_LIMIT = 19      # JET.report_opt on analyze(::String), scoped to Dendro

        if (VERSION.major, VERSION.minor) == (JET_JULIA.major, JET_JULIA.minor)
            sound = JET.get_reports(JET.report_package(Dendro; target_defined_modules = true, mode = :sound))
            length(sound) < SOUND_LIMIT && @info "JET sound below limit; lower SOUND_LIMIT to $(length(sound))"
            @test length(sound) <= SOUND_LIMIT

            opt = JET.get_reports(JET.report_opt(Tuple{typeof(Dendro.analyze), String}; target_modules = (Dendro,)))
            length(opt) < OPT_LIMIT && @info "JET opt below limit; lower OPT_LIMIT to $(length(opt))"
            @test length(opt) <= OPT_LIMIT
        end
    else
        @test true skip = true
    end
end
