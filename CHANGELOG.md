# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `analyze_corpus(paths; min_size, language, baseline, cut)`, a project-level
  entrypoint. It analyzes every file against a baseline built from the corpus
  (unless one is passed), so relative scoring works with no setup, and appends
  cross-file duplicates.
- Cross-corpus duplicate detection. `find_duplicates(paths; min_size, language)`
  finds functions duplicated across files, tolerant to identifier renaming and
  literal-value changes (Type-2 clones), by hashing each function's node-type
  sequence. Each cluster of two or more is one `:duplicate` finding whose
  `locations` list every member. `min_size` (named-node count) gates trivial
  functions. Suppressed by `dendro-ignore: duplicate` on any member.
- Inline suppression directives in comments: `dendro-ignore` for the same or next
  line, `dendro-ignore: cyclomatic, parameter_count` for named metrics, and
  `dendro-ignore-file` for a whole file. Works in every supported language. An
  unknown metric name warns. A suppressed finding is marked, not dropped, so
  `report` prints a count of suppressions and `active(findings)` returns the
  unsuppressed findings for gating.

### Changed

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
