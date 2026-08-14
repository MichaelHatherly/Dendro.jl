# JET static analysis over Dendro's own modules. Run it with `just jet`; CI runs the same
# recipe in a job of its own.
#
# This sits outside the test suite in an environment of its own. Sound analysis is an
# inference workload rather than a test, it is the longest single check by a wide margin,
# and the ratchet below reads counts that one Julia and JET pairing produces. Inside the
# suite it ran in nine matrix cells where at most one did the analysis the ratchet reads,
# and it shared a process, and on ubuntu a capped heap, with the other 2965 tests.
#
# Basic mode is a zero-tolerance gate: a type-level regression, a call that admits a
# no-method branch, fails here rather than at runtime.
#
# Sound mode and the optimization analyzer flag far more, mostly intentional dynamic
# dispatch on Dendro's design (function-valued rules, tree-walks over `Any` nodes).
# Rather than gate at zero, ratchet: cap the count at its current value so it can
# only fall. Lower a limit whenever the count drops, that locks in the cleanup;
# never raise one without a reason. The counts depend on the Julia and JET versions,
# so a toolchain bump is answered by re-measuring and recording what moved, the same
# as a code change. The sound count rose from 462 to 472 with the Julia 1.12.6 / JET
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
# Flooring a control-free function at the block size raised sound from 1063 to 1065, opt
# unchanged: `unit_floor` threads the abstract `min_size::Integer` the clone signatures
# already carry, so `size < unit_floor(...)` widens to `Any` where `size < min_size` did
# before and its `2 * min_size` adds one uncovered `*(::Int64, ::Integer)` match, and the
# extracted `subtree_any(pred::P)` higher-order walk analyses `pred` generically as `Any`
# in boolean context, the same intentional abstraction the other passes already count.
# Measuring cross-cutting breadth against a definition's own reach raised sound from 1065
# to 1066, opt unchanged: `corpus_visibility` lifts the corpus-path generator out of
# `corpus_references` so the graph builder can read the visibility it already resolves, and
# that one closure is now analysed from two call sites rather than one. Everything else in
# the diff is a rename. Registering a language from the config (`profile.jl`, `resolve.jl`,
# `config.jl`) raised sound from 1066 to 1118, opt unchanged: the `[languages]` applier adds
# two more of the `for (key, value) in table` walks over the `Dict{String, Any}`
# `TOML.parsefile` returns, the shape each existing applier already carries at fourteen
# reports apiece, and threading a resolved `profiles` registry through `parse_corpus`,
# `source_files`, `collect_corpus`, and `mermaid` widens those four keyword-argument
# lowerings, both kinds already counted. It first measured 1170: narrowing `queries_dir` to
# `String` and typing the per-language applier's `name` and `table` removed 52, so what is
# left is the applier and kwarg shape rather than inference that could be recovered.
# Resolving a reference qualified by its namespace raised sound from 1118 to 1120, opt
# unchanged: `reference_name` adds one, walking an `Any` node's parent and children the
# same way the metric passes already do, and `splice_graph` adds one over the
# `inclusion_components` it replaces, its generator closure now building the component map
# as well as the edge list. Everything else in the diff moves reports between files:
# `baseline_from` and `sample_chunk!` are counted under `baseline.jl` rather than
# `corpus.jl`, and `member_visible` reads a `VisibilityIndex` where it read a `SymbolTable`.
# The architecture rules over the corpus file graph (`file_graph.jl`, `back_edge.jl`,
# `dependency_cycle.jl`, `hub.jl`, `incoherent_package.jl`, `scattered.jl`, and the clone
# ranking in `clones.jl`) raised sound from 1120 to 1322 and opt from 22 to 23: seven more
# corpus passes, each carrying the keyword-argument lowering and `Any`-node walk every
# existing cluster pass already counts, re-counted through `analyze`'s new call edges, and
# `rank_clones!` dispatches through a function-valued comparison of the kind the rule vector
# already incurs. Basic mode stays at zero throughout, so none of this is a type-level
# regression. Extracting `analyze`'s pass sequence into `clone_clusters` and
# `relational_clusters` and moving the coordination into `analyze.jl` then brought sound to
# 1312, ten fewer sites of the same kinds. Resolving the corpus once per scan
# (`resolve_linkage`, and the `linkage.jl`/`resolution.jl` split) brought it to 1308, opt
# unchanged: five passes stopped re-resolving the corpus, so five `corpus_references` and
# `corpus_visibility` call edges and `public_surface`'s second walk are gone, each of which
# carried the keyword-argument lowering and `Any`-widening every corpus pass counts. Measured
# in two steps, which is worth recording: the refactor alone read 1314, since `resolve_linkage`
# and `DeclaredLinkage` add two sites of that same kind, and the location labels then took it
# to 1308, moving `label_path` out to `placement.jl` and having `audience_reps` return
# `Location`s rather than indices the caller re-wraps.
#
# The review fixes then took the count from 1308 to 1303, so the limit drops to match.
# Measured under `Pkg.test`, which is what CI ran then and what the numbers above are on. A
# bare `report_package` against this project read exactly one lower, since `Pkg.test`
# analyses with `--check-bounds=yes`; the deltas below are the same either way, the absolute
# figure is not. Resolving each corpus path once per scope into `Scope.rels` and reading it
# through `in_scope` took `analyze.jl` from 50 to 40: the inline `relpath(realpath(...))` per
# location was re-resolving inside a closure the scoping filter and the parallel per-file
# pass both widened through. Against that, `cluster_back_edge`'s `floors` keyword adds 2,
# irreducibly, since a caller may name either floor and the NamedTuple's type is therefore
# unknown at the callee; the `@NamedTuple` assertion on the merge stops the widening
# travelling further, and dropping partial override would buy the last 2 at the cost of the
# API. `linkage.jl` adds 2 for `resolved_targets`, the new seam between the linkage
# resolution and the file graph's node lookup, and `gate.jl` 1 for `relative_to`. Two
# measured non-costs worth recording: the iterative Tarjan walk and the `FileGraph.modules`
# field each read zero, so neither the explicit frame stack nor the extra field cost
# inference anything.
#
# The pattern rules (`patterns.jl`, `fragments.jl`, `pattern_tests.jl`, and the `[patterns]`
# plumbing in `config.jl` and `corpus.jl`) raised sound from 1303 to 1428 and opt from 23 to
# 27: a second query family carries a TOML applier of the shape each existing one has, a
# coercer per declared field over the `Any` values `TOML.parsefile` returns, and an
# `Any`-node tree walk per compiled query, every kind already counted. It first measured
# 1507. Typing the `specs`, `fragments`, and `profiles` parameters the new code threads, and
# narrowing the offsets and query text it walks to `Int` and `String`, removed 79, so what is
# left is the applier and the walk rather than inference that could be recovered. The four
# new opt reports are `apply_pattern!`'s coercion branches, the same dispatch on an `Any`
# TOML value that `apply_language!`'s three already carry; `@inline`, which folded the
# `config_*` helpers off this count, moves nothing there, since the dispatch is on the value
# rather than on the conversion.
# `:divisible_package` (`divisible_package.jl`, plus `directory_findings` in `report.jl` and
# `append_gated!` in `analyze.jl`) raised sound from 1428 to 1473, opt unchanged at 27: one
# more corpus pass carrying the keyword-argument lowering and `Any`-node walk every existing
# cluster pass already counts, re-counted through `analyze`'s new call edge, and a gated call
# reached through a thunk of the kind `rank_clones!`'s function-valued comparison already
# incurs. One measured non-cost: narrowing `read_divisible` from an anonymous NamedTuple
# union to `Union{DirectoryReading, Nothing}` moved nothing at all, so the union return was
# never what the count was reading. The struct stays because it names the thing, not because
# it bought anything here.
#
# Guard declarations and the anchored suppression directive raised sound from 1473 to 1482:
# `PatternSpec` carries one more declared field and a convenience constructor, two reports of
# the shape each existing field already has; typing `suppressions`' `rules` keyword puts its
# keyword-argument lowering on the signature for four more; three land in frames that carry
# no file. It first measured 1495, where `metric_names` built its result with
# `append!(::Vector{Symbol}, ::Tuple)`. That reaches Base's generic iterator path, costing
# fifteen reports at the call and two more where `suppressions` reads the widened result, so
# the parameter is typed and the walk is over a concrete vector again. Rewriting the append
# as a `push!` loop over the tuple instead measured 1496, one worse than the splat it
# replaced: the iteration moves out of Base and into a Dendro frame, where it counts.
#
# The cross-corpus library passes (`libraries.jl`, and the `[libraries]` plumbing in
# `config.jl`, `corpus.jl`, `query_index.jl`, `main.jl` and `analyze.jl`) raised sound from
# 1482 to 1687 and opt from 27 to 32. The rise is 120 in `libraries.jl`, 32 in `config.jl`,
# 17 in `clones.jl`, 13 in `corpus.jl`, 10 in `main.jl`, 6 in `query_index.jl`, 3 in
# `analyze.jl`, 1 in `gate.jl` and 6 in frames that carry no file, against 3 fewer in
# `suppress.jl`: one more corpus pass carrying the keyword-argument lowering and `Any`-node
# walk every existing cluster pass counts, a `[libraries]` applier of the shape each existing
# one has, and a keyword added to `build_index` and to `parse_corpus` widening two more of
# those lowerings, every kind already counted. The five opt reports are `apply_library!`'s
# coercion branches, the same dispatch on an `Any` TOML value `apply_language!` and
# `apply_pattern!` already carry, and `reference_publicness` reading the function-valued
# `Linkage.is_public`, which the reachability resolver already counts.
#
# Narrowing was measured twice here and made it worse both times, so 1687 is the shape rather
# than inference that could be recovered. Guarding `as_libraries` and `library_roots` with
# `isa` before the value reaches a constructor read one report higher. Typing the `libraries`
# keyword the whole way through `analyze` and `override_config` read nine higher: a keyword
# annotation whose caller still hands over an `Any` turns that signature into an uncovered
# method match, so the reports move into `config.jl` instead of going away. The passes that
# recovered 52 and 79 did it by typing internal parameters that were bare, and this one has
# none: what the library code threads is typed already.
#
# Moving the reference cache into a scratch space and collecting stale entries raised sound
# from 1687 to 1711, all of it in `libraries.jl`. Fourteen sit on the new lines themselves:
# five at `sweep_references`' signature and one at the `rm` inside it, two at `best_effort`'s
# and four at its `@debug`, one at the `touch` guarding a hit and one at the sweep's call
# site. The other ten are `store_reference`'s existing body read through a closure now that
# it passes a `do` block to `best_effort` rather than opening `try` inline.
#
# That last ten is the price of the extraction, and it buys the invariant being stated once
# instead of five times: a cache is an optimisation and must not be able to break a scan.
# Writing the `try`/`catch`/`@debug` out at each of the five sites would read lower here and
# leave Dendro's own duplicate pass with something to say. `best_effort`'s callback is
# already `::F where {F}`, so this is the shape rather than inference to recover, the same
# finding the two narrowing attempts above reached.
#
# Replacing `Serialization` with a format Dendro owns raised sound from 1711 to 1722 and left
# opt at 32. Those eleven are what a hand-written codec costs: `serialize` and `deserialize`
# were one frame each, where the encoder, the reader and the bounds check every length passes
# through are frames JET can see and count. The reader doing that checking in Dendro rather
# than behind a stdlib call is the whole point of the format, so this is the shape rather
# than inference to recover.
#
# Reading a file's top-level code as units lowered sound from 1722 to 1710 and raised opt
# from 32 to 33. The fall is a redistribution rather than a saving: `report.jl` drops 43,
# `rules.jl` 15 and `baseline.jl` 7, against 22 in the new `scoring.jl` that the scalar
# scoring left `report.jl` for, 21 in `units.jl` where the unit model now lives, and 10
# across `query_index.jl`, `clones.jl` and frames that carry no file. `unit_findings!` takes
# the abstract `Unit` where it took the `FunctionUnit` struct, so the per-unit frames are
# counted at that signature rather than at each concrete reader.
#
# The one opt report is `apply_pattern!`'s new `scope` branch, the same dispatch on an `Any`
# TOML value the four branches beside it already carry. Narrowing it would mean narrowing
# all five, so this is the shape rather than inference to recover.
#
# The `:change` diagram raised sound from 1710 to 1722. `with_base_corpus` carries most of
# it: the ratchet's `git archive` block became a callback so the diagram could reuse it, and
# a callback is analysed at `::F` with the git plumbing inside it as frames JET can see and
# count. Two shapes were measured and kept, worth four reports each. `mktempdir` with a block
# wraps the callback in a second closure that its own signature types as `Any`, so a `try`
# does the cleanup one layer down instead. A keyword argument splits a method into a
# `kwcall` wrapper and a body, and every report against the body is then raised twice, so
# `keyword` is positional. Two were measured and reverted, costing four: annotating
# `ref::AbstractString` forces a `string(since)` at the gate's call site, and typing the
# `base` keyword as a `Union` adds a split, each a frame of its own. The remainder is the six
# functions the view is built from, counted at their own signatures.
#
# The within-file half of that diagram raised sound from 1722 to 1755. A first measurement
# put it at 1772, of which `state_arrow` and `weight_label` were seventeen: both were
# declared `::Real` so that every comparison and subtraction under them dispatched
# dynamically, for the sake of two callers, one counting whole references and one counting
# the fractions a split reference leaves. Both take `Float64` now and the file-level caller
# converts. The remaining thirty-three are the unit pass reaching `clone_features` for the
# body digests that let a rename read as a rename, and its callback returning a pair of
# dictionaries where the file-level one returns a single dictionary.
#
# A `--since` flag and a top-level `ignore` config key raised sound from 1755 to 1763, all
# eight in the two frames that already dominate this list. `apply_key!` is four: one more
# `elseif` over an `Any` TOML value, counted at both of its signatures, which is what every
# branch beside it costs. `parse_args` is two and the `CLIOptions` constructor one, the flag
# and the field it carries. The last is merging the configured patterns with the keyword's.
# One narrowing was measured and reverted, costing five: a `scan_ignores(config, ignore)`
# helper reads its second argument as `Any`, so `isempty` and `collect` under it dispatch
# dynamically and the helper is counted at its own signature too. `String[config.ignore;
# ignore]` at the call site is four cheaper and says the same thing.
#
# Reading repositories through libgit2 raised sound from 1763 to 1774. The eleven are the
# `ccall` layer and the tree walk: `git_patch_get_line_in_hunk` hands back a `Ptr{DiffLine}`
# that `unsafe_load` reads, and `git_patch_from_diff` a `Ptr{Cvoid}` the free path takes, so
# the pointer handling the subprocess hid behind `read(::Cmd, String)` is now frames JET can
# see and count. The `treewalk` callback carries the rest: it is analysed at `::F` with the
# blob write inside it, the same shape `with_base_corpus` was already charged for above.
# Unlike the entries above this one, no narrowing was attempted or measured; the raise was
# taken directly.
#
# Moving to JET 0.12 took sound from 1774 to 1371 and left opt at 33. Every absolute figure
# above it is on JET 0.10.15 under `Pkg.test` and does not reproduce here: 0.11 rebuilt
# `report_package` on Revise, so which definitions it reaches changed, and this runs without
# the `--check-bounds=yes` that `Pkg.test` imposed. The deltas and the narrowing attempts
# recorded above still hold, since they are about Dendro's shape rather than JET's, but
# compare a new measurement against 1371 and not against anything before it. Basic mode is
# still at zero, so nothing in the bump is a type-level regression. The one call that had to
# change is the module filter: 0.12 removed `target_defined_modules`, and `target_modules`
# is the replacement it names. Dendro is one module with no submodules, so the two select
# the same frames.
#
# The `:distant_definition` pass raised sound from 1371 to 1377 and left opt at 33. Five of
# the six name `distant_definition.jl` and all five are the keyword-argument lowering every
# `cluster_*` pass carries: three `getfield(::NamedTuple, ...)` reads for `band`, `cut` and
# `min_defs`, the `diff_names` check over the keyword names, and the kwarg body method at
# `::Any` arguments. The sixth is the call edge `relational_clusters` gained. No new kind,
# and no narrowing is available short of dropping the keyword interface every sibling pass
# is written to, so the raise was taken directly.
#
# The near-miss multiset bound raised sound from 1377 to 1379 and left opt at 33. Both are
# one report twice over: `CloneUnit` and `ProjectRegion` each gained a field, so the
# all-`::Any` constructor calls those two records already reported carry one more argument,
# and one further `UnanalyzedCallReport` falls out of the wider `CloneUnit`. The `@def_name`
# parent map that landed beside it added none.
# Dumping every report before and after confirms it: keyed without line numbers,
# the whole diff is `CloneUnit(::Any x7)` becoming `(::Any x8)` and `ProjectRegion(::Any x9)`
# becoming `(::Any x10)`. The field types are not why, and no narrowing follows from fixing
# them: both records are built inside `clone_units`/`project_regions`, which sound mode
# enters at `::Integer` and `::Symbol`, so every field reads as `::Any` whatever it is
# declared as. Holding the sorted prefixes outside the records instead would take
# `near_miss_edges!` to six parameters and trip `parameter_count`, trading one gate for
# another.
#
# That dump also showed this count is not stable to the report. Two runs over the identical
# tree gave 1378 and 1379, and the two disagree on the printed signature of
# `with_base_corpus` and of `mermaid`'s kwarg body, and on one `fold_branches` report, none
# of which either change touches. So the number carries about one report of run-to-run
# variance and the limit is the higher observation, not the lower. Read a rise of one as
# noise and re-measure before recording it; a rise of several is a real move.

using Dendro
using JET
using Test

const SOUND_LIMIT = 1379  # JET.report_package(Dendro; mode = :sound).
const OPT_LIMIT = 33      # JET.report_opt on analyze(::String), scoped to Dendro

@testset "JET" begin
    JET.test_package(Dendro; target_modules = (Dendro,), mode = :basic)

    sound = JET.get_reports(JET.report_package(Dendro; target_modules = (Dendro,), mode = :sound))
    length(sound) < SOUND_LIMIT && @info "JET sound below limit; lower SOUND_LIMIT to $(length(sound))"
    @test length(sound) <= SOUND_LIMIT

    opt = JET.get_reports(JET.report_opt(Tuple{typeof(Dendro.analyze), String}; target_modules = (Dendro,)))
    length(opt) < OPT_LIMIT && @info "JET opt below limit; lower OPT_LIMIT to $(length(opt))"
    @test length(opt) <= OPT_LIMIT
end
