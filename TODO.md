# TODO

Noticed while working, out of scope where they were found.

- The ratchet has no command-line route. `errors(paths; since)` is the gate that makes
  Dendro adoptable on a codebase that is not yet clean, and `CLIOptions` carries no
  `since`, so `dendro --check` can only read the absolute floor. A CI job that is not a
  Julia test suite has to be clean from day one or not gate at all. Wants a `--since`
  flag reaching the same code path.
- Path ignores are unreachable outside Julia. `ignore` is a keyword on `analyze` and
  `errors`, `CONFIG_KEY_ORDER` has no top-level `ignore`, and there is no flag. A project
  with a vendored tree cannot exclude it from a `dendro` run, and cannot record the
  exclusion in `.dendro.toml` for either route. A config key would give the CLI the
  feature too.
