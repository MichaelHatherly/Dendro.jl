# Scoring and metrics

```@meta
CurrentModule = Dendro
```

## Scoring

Every scalar metric reports two scores, and a function is flagged when either
fires:

- **Absolute**: the value against a fixed band (cyclomatic warn >10 / high >20,
  nesting >3, parameters >4). A fixed target a codebase can improve toward.
- **Relative**: the value's percentile against the corpus. Catches functions
  worse than the codebase's own norm, the signal that matters in review.

Absolute alone misses outliers in a uniformly-weak codebase; relative alone
calls a uniformly-weak codebase fine. Reporting both avoids each trap.

## Metrics

Scalar (per function): cyclomatic complexity, cognitive complexity (the same branch
points weighted by the nesting they sit under, so a deeply-nested function scores
worse than a flat one of the same path count), length, maximum nesting depth,
parameter count, boolean complexity (the most `&&`/`||` operators joined into one
expression).

Flag (presence is the finding): swallowed errors (empty catch clauses), stub
markers (`TODO`/`FIXME`/`XXX`/`HACK` comments), empty function bodies, a `return`
inside a finally clause (which discards a pending error or return value), identical
operands (`x == x`, `a && a`), a conditional whose branches are all identical
(`if c then X else X`), unused parameters, unused locals, and broad catches (a bare
`except:`, `except BaseException`, Java `catch (Throwable)`, C++ `catch (...)`,
Ruby `rescue Exception`, PHP `catch (Throwable)`, the handlers that swallow
interrupts and exits; the merely-wide `except Exception` tier is left alone). An
optional rule flags code after an unconditional `return`, `break`, or `throw`.

Unused parameters and locals read the lexical bindings: a parameter or local
binding whose name nothing in its function references is dead weight. The use-test
is by name over the whole unit, the conservative reading, so a same-named reference
in a nested closure counts as a use. A leading underscore opts a name out, the
cross-language deliberate-unused convention. A bodyless declaration keeps its
parameters (they are its signature), an empty or stub body is already the
`empty_body` finding, and a top-level binding belongs to `:unreferenced`, so none
of those double-report. A language whose parameters carry no names (bash) or whose
scopes query captures no locals (php) reports nothing for that half.

Two more binding readings are optional rules: `local_count` (distinct local names
bound in a function) and `shadowed_variable` (a fresh local binding hiding an
enclosing one). See [Custom rules](@ref).

Each metric is a [rule](@ref "Custom rules"). The set above is the default; a caller
can add their own or opt into rules that are off by default.

Relational (computed across the corpus, not per function): duplicates
([below](@ref "Duplicate detection")), naturalness, within-file cohesion, and
cross-file placement. Naturalness scores each function's token sequence against a
per-language trigram model of the rest of the corpus, in bits per token. The corpus
model is interpolated with a per-file cache model (after Tu et al., "On the Localness
of Software"), so a function is read against its own file's idiom, not just the
corpus's, which sharpens genuine outliers and quiets file-consistent patterns. A
surprising, unidiomatic function scores high, and surprise correlates with bugs.
Reported as `:unnatural` with both scores, the absolute cross-entropy band and the
corpus percentile. A language with too few tokens to model is skipped.

Cohesion asks whether a file's functions group by usage
([below](@ref "Cohesion and placement")). Placement asks whether a unit sits in the
right file, scattering whether a file's units belong to one module, and reachability
whether a private definition is dead, reported as `:unreferenced`
([below](@ref "Cohesion and placement")).
