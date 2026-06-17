# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `analyze(path; base, cut, min_size, language)` takes a file or folder. A folder
  recurses for analysable files; either way a baseline is built from the corpus
  (the folder's files, or the single file's own functions), so relative scoring
  works against the input's own distribution with no setup. `base` scopes to a git
  diff, reporting only functions changed against that ref. Every analysis reports
  per-function metrics and cross-file duplicates, tolerant to identifier renaming
  and literal-value changes (Type-2 clones), each cluster of two or more functions
  one `:duplicate` finding whose `locations` list every member. `min_size`
  (named-node count) gates trivial duplicates, suppressed by
  `dendro-ignore: duplicate` on any member.
- Inline suppression directives in comments: `dendro-ignore` for the same or next
  line, `dendro-ignore: cyclomatic, parameter_count` for named metrics, and
  `dendro-ignore-file` for a whole file. Works in every supported language. An
  unknown metric name warns. A suppressed finding is marked, not dropped, so
  `report` prints a count of suppressions and `active(findings)` returns the
  unsuppressed findings for gating.

### Changed

- One public analysis entrypoint, `analyze`. It takes a file or a folder, with
  optional git-diff scoping (`base`) and a baseline auto-built from the corpus. The
  separate `analyze_diff` (0.1.0), `analyze_corpus`, and `find_duplicates`
  entrypoints are removed, folded into `analyze`.
- `analyze` always builds its own baseline, so the baseline API is no longer
  public: `build_baseline`, `save_baseline`, `load_baseline` (0.1.0), the
  `baseline` keyword, and the `Baseline` export are removed, along with the JSON
  dependency they needed.
- `analyze` returns `Findings`, an `AbstractVector{Finding}` that prints as a
  report, so its result renders directly in the REPL. The `report` (0.1.0) function
  is removed; write the report elsewhere with `show(io, MIME("text/plain"), findings)`.
- Dendro exports nothing. The API (`analyze`, `active`, `Finding`, `Findings`,
  `Location`) is marked `public` instead, so `using Dendro` no longer brings names
  into scope; import what you call or qualify with `Dendro.`. The `public` keyword
  raises the minimum Julia to 1.11.
- A `Finding` now spans a set of `Location`s rather than a single file/line/unit,
  so a relational metric like `:duplicate` reports every site it covers. Per-file
  metrics still fire at one location.

## [0.1.0]

### Added

- Scalar metrics per function: cyclomatic complexity, length, maximum nesting
  depth, parameter count, each with a documented absolute severity band.
- Flag metrics: swallowed errors (empty catch clauses), stub markers
  (`TODO`/`FIXME`/`XXX`/`HACK`), and empty function bodies.
- Dual scoring. Every `Finding` carries the absolute band and, with a `Baseline`,
  the corpus percentile, so outliers surface against both a fixed standard and
  the codebase's own distribution.
- `Baseline` over a corpus with JSON persistence (`build_baseline`,
  `save_baseline`, `load_baseline`).
- `analyze` for a whole file, `analyze_diff` to score only the functions a git
  diff touched, and `report` for text output.
- Lazy parser resolution: a language name loads its `tree_sitter_<lang>_jll` on
  demand, so Dendro depends on no grammars itself.
- Language profiles for bash, c, cpp, go, java, javascript, julia, php, python,
  ruby, rust, typescript.
