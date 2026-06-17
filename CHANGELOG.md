# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
