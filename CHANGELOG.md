# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Flag metrics `unused_parameter` and `unused_local`: a parameter or local binding
  whose name nothing in its function references. The use-test is by name over the
  whole unit, so a reference in a nested closure counts; a leading underscore opts
  a name out. Bodyless declarations, empty and stub bodies, and top-level bindings
  are not reported (the latter belong to `unreferenced`). Both are built-in rules,
  suppressible inline and toggleable from `[rules]` in `.dendro.toml`.
- The Julia scopes query captures a local binding only from a statement-position
  assignment, so a call-site keyword argument (`sort!(xs; by = f)`) and a
  NamedTuple field (`(added = true,)`) no longer read as bindings. The bash scopes
  query captures `variable_name` references, so `$x` resolves to its assignment.
- Optional rules `local_count` (distinct local names bound in a function, band
  10/15) and `shadowed_variable` (a fresh local binding hiding an enclosing one).
  The Julia scopes query splits binding kinds to support the latter: a `for`/`let`
  head is a fresh binding, a statement assignment rebinds an enclosing local, so
  the accumulator idiom never reads as a shadow.
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
- Scalar metrics per function: cyclomatic complexity, length, maximum nesting
  depth, parameter count, each with a documented absolute severity band.
- Flag metrics: swallowed errors (empty catch clauses), stub markers
  (`TODO`/`FIXME`/`XXX`/`HACK`), and empty function bodies.
- Dual scoring. Every `Finding` carries the absolute band and the corpus
  percentile, so outliers surface against both a fixed standard and the codebase's
  own distribution.
- Inline suppression directives in comments: `dendro-ignore` for the same or next
  line, `dendro-ignore: cyclomatic, parameter_count` for named metrics, and
  `dendro-ignore-file` for a whole file. Works in every supported language. An
  unknown metric name warns. A suppressed finding is marked, not dropped, so the
  rendered report shows a count of suppressions and `active(findings)` returns the
  unsuppressed findings for gating.
- A `Finding` spans a set of `Location`s rather than a single file/line/unit, so a
  relational metric like `:duplicate` reports every site it covers. Per-file
  metrics fire at one location.
- `analyze` returns `Findings`, an `AbstractVector{Finding}` that prints as a
  report; render it elsewhere with `show(io, MIME("text/plain"), findings)`.
- Lazy parser resolution: a language name loads its `tree_sitter_<lang>_jll` on
  demand, so Dendro depends on no grammars itself.
- Language profiles for bash, c, cpp, go, java, javascript, julia, php, python,
  ruby, rust, typescript.
- Dendro exports nothing. The API (`analyze`, `active`, `github_annotations`,
  `Finding`, `Findings`, `Location`, `Rule`, `BUILTIN_RULES`, `OPTIONAL_RULES`) is
  marked `public`, so `using Dendro` brings no names into scope; import what you
  call or qualify with `Dendro.`. The `public` keyword sets the minimum Julia to
  1.11.
