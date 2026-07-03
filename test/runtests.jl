using TestItemRunner

# Filter by tag when test args are given: `Pkg.test(test_args = ["suppress"])`
# runs only items tagged :suppress. No args runs everything.
@run_package_tests filter = ti -> isempty(ARGS) || any(t -> String(t) in ARGS, ti.tags)
