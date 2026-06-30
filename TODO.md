# TODO

- `errors` (the `Pkg.test` gate and ratchet) passes `rules = BUILTIN_RULES` to
  `analyze`, so it ignores a `.dendro.toml`: a project that retunes a scalar band or
  toggles a rule sees the change in `analyze` and the CLI but not in the gate. Decide
  whether the gate should resolve from the config like `analyze` does, then thread the
  config through `errors`/`base_floor_counts` if so.
- Migrate the `code-quality` skill's `scripts/scan.jl` to call the CLI
  (`julia --project=@dendro-scan -m Dendro --base <ref> <paths>`) instead of
  dev-loading and hand-calling `analyze`/`active`. Lives in the skills repo.
