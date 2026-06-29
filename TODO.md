# TODO

## Performance, deferred from the corpus-binding-graph review

- Cache `ScopeCaptures` on `ParsedFile`. `collect_scopes` runs three times per file per
  `analyze` (parse, `file_symbols!`, `unbound_references`), each re-walking the full
  capture set. Needs a field on `ParsedFile`, an architecture change.
- Build a suffix index in `visible_defs`. `suffix_match` (`linkage.jl`) scans the whole
  corpus per import statement, so Rust/Java/PHP resolution is O(n²) in file count.
  Worth doing only if a large corpus shows the cost.
