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
# (`config.jl`, `main.jl`) raised sound from 601 to 852 and opt from 14 to 21: the
# `.dendro.toml` loader walks the `Dict{String, Any}` `TOML.parsefile` returns (every
# band, rule, and `[clones]` threshold coerced from an `Any` value), and `main`/`run_cli`
# re-enter `analyze`'s keyword-argument and `Vector{String}` paths machinery, the same
# `Any`-value and kwarg-lowering dispatch already counted, at new sites. Routing every
# coercion through the inlined, `isa`-guarded `config_*` helpers then dropped sound from
# 852 to 836 and opt from 21 to 20: the guard narrows each `Any` TOML value to a concrete
# type before conversion, and inlining folds the residual conversion into the caller,
# attributed to Base, off the Dendro-scoped opt count. Threading the corpus fan-outs
# (`parallel.jl`, and the parallelised passes in `clones.jl`, `linkage.jl`, `naturalness.jl`,
# `corpus.jl`, `placement.jl`) raised sound from 836 to 1020 and opt from 20 to 21:
# `Threads.@spawn` schedules a Task closure and `parallel_map!`/`parallel_chunks` dispatch
# through a function-valued argument, so each fan-out's `Any`-node walk is analysed inside a
# spawned closure too, the same intentional dynamic dispatch already counted, at new sites
# across the fan-outs. Folding the per-item fan-outs through `parallel_flatmap` and
# assigning `analyze`'s `scope` once then dropped sound from 1020 to 980 and opt from 21
# to 20: the shared fold replaces per-site append loops over `Any`-inferable partials, and
# the single assignment lets the scoring closure capture `scope` concretely instead of as
# a `Core.Box`. The unused-binding flags (`unused_parameters`, `unused_locals`) raised
# sound from 980 to 988, opt unchanged: two more rules dispatched through the
# function-valued rule vector, whose `Any`-typed findings feed the same kwarg-lowering
# and `Any`-collection sites already counted, no new kind. The optional
# `shadowed_variable`/`local_count` rules raised sound to 989: one more site of the
# same rule-vector dispatch. The optional `fan_out` rule raised sound to 990: the
# same again. The reimplementation pass raised sound to 1054 and opt to 21: a new
# corpus pass (`cluster_reimplementations` and its config plumbing) adds the same
# kwarg-lowering and `Any`-widening sites the other cluster passes carry, re-counted
# through `analyze`'s new call edges; only five reports name the new code, all of
# those kinds. Rooting a macro-consumed definition through the function-valued
# `Linkage.external_root` field, like the other per-language hooks, raised sound from
# 1054 to 1063 and opt from 21 to 22: the reachability graph builder dispatches through
# it for every definition, and `julia_external_root` walks the `Any`-node ancestor chain,
# the same intentional dynamic dispatch and `Any`-node tree walk already counted.
@testitem "JET" tags = [:jet] begin
    import JET

    if isempty(VERSION.prerelease)
        JET.test_package(Dendro; target_defined_modules = true, mode = :basic)

        JET_JULIA = v"1.12"
        SOUND_LIMIT = 1063  # JET.report_package(Dendro; mode = :sound).
        OPT_LIMIT = 22      # JET.report_opt on analyze(::String), scoped to Dendro

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
