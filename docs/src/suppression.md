# Suppressing findings

```@meta
CurrentModule = Dendro
```

Some flagged code is fine in context. A comment directive accepts a specific
finding so Dendro skips it without muting the tool or refactoring sound code.
The mechanism reads comment nodes, so it works in every supported language.

- `dendro-ignore` suppresses every finding on the same line or the line directly
  below, so a trailing comment or a comment above a declaration both work.
- `dendro-ignore: cyclomatic, parameter_count` suppresses only the named metrics.
- `dendro-ignore-file` (or `dendro-ignore-file: cyclomatic`) suppresses the whole
  file, for generated or vendored code.

```julia
# dendro-ignore: parameter_count
function build(a, b, c, d, e, f)   # one keyword per field, accepted
    ...
end
```

Metric names are the active rules' names plus the relational `duplicate` and
`near_duplicate`: by default `cyclomatic`, `cognitive_complexity`,
`function_length`, `nesting_depth`, `parameter_count`, `boolean_complexity`,
`empty_catch`, `stub_marker`, `empty_body`, `return_in_finally`,
`identical_operands`, `duplicate_branches`, `duplicate`, `near_duplicate`,
`unnatural`, `low_cohesion`, `misplaced`, `scattered`. A custom rule's
name is accepted too. An unknown name warns, so a typo does not silently disable a
check. `dendro-ignore-file: low_cohesion` is the usual way to accept a file that is
meant to be a grab-bag.

Suppression marks a finding rather than dropping it. Printing a findings vector
lists the active findings and a footer counting the suppressed ones, and
[`active`](@ref) returns only the unsuppressed findings for gating.

## Ignoring paths

`dendro-ignore-file` mutes one file from inside it. Vendored and generated trees
you do not own want the opposite: exclusion from the outside, by path, without
touching the source. The `ignore` keyword takes gitignore-style patterns, matched
against each path relative to the scanned folder.

```julia
analyze("."; ignore = ["vendor/", "deps/**", "*.generated.jl"])
```

A leading `!` re-includes, a trailing `/` matches directories only, `*` and `?`
stop at a separator, `**` spans them. As in gitignore, a file under an excluded
directory cannot be re-included.

Ignored files are dropped before parsing, so they are neither flagged nor counted
in the baseline. This matters even in `base` review mode: an unchanged vendored
tree never appears in findings, but left in the corpus it would still skew the
percentile every scanned file feeds. Ignoring it keeps relative scoring honest.
Patterns apply to folder scans, not a single named file.
