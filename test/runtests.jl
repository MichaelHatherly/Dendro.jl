using TestItemRunner

# The reference-index cache writes under `$XDG_CACHE_HOME/dendro/references`. Point it at a
# throwaway directory for the whole run, items and the subprocesses `test/parallel.jl`
# spawns alike, so a suite run never touches a developer's real cache and no entry survives
# into the next one.
ENV["XDG_CACHE_HOME"] = mktempdir(; cleanup = true)

# `@run_package_tests` walks the whole package directory for test items, so a git worktree
# checked out beneath it (`.claude/worktrees/<branch>`) contributes a second copy of every
# item and multiplies the reported counts. Every item of this suite lives under this
# checkout's own `test/`, so a path outside it belongs to another tree.
const SUITE_DIR = normpath(@__DIR__)
in_suite(filename) = startswith(normpath(filename), SUITE_DIR)

# Filter by tag when test args are given: `Pkg.test(test_args = ["suppress"])`
# runs only items tagged :suppress. No args runs everything.
@run_package_tests filter = ti -> in_suite(ti.filename) && (isempty(ARGS) || any(t -> String(t) in ARGS, ti.tags))
