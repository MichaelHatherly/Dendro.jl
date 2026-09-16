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

[Metric reference](@ref) tabulates every name below with its default band and whether it
runs by default. This section says what they measure.

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
interrupts and exits; the merely-wide `except Exception` tier is left alone). The
optional `unreachable_after_jump` flags code after an unconditional `return`, `break`,
or `throw`.

Unused parameters and locals read the lexical bindings: a parameter or local
binding whose name nothing in its function references is dead weight. The use-test
is by name over the whole unit, the conservative reading, so a same-named reference
in a nested closure counts as a use. A leading underscore opts a name out, the
cross-language deliberate-unused convention. A bodyless declaration keeps its
parameters (they are its signature), an empty or stub body is already the
`empty_body` finding, and a top-level binding belongs to `:unreferenced`, so none
of those double-report. A language whose parameters carry no names (bash) or whose
scopes query captures no locals (php) reports nothing for that half.

Three more coupling and binding readings are optional rules: `local_count`
(distinct local names bound in a function), `shadowed_variable` (a fresh local
binding hiding an enclosing one), and `fan_out` (distinct callables a function
invokes). See [Custom rules](@ref).

`comment_density` is a fourth, and it reads narration where those three read coupling:
the percentage of a definition's lines given over to comment. A generated function often
arrives with its rationale written into the body, a comment above each statement
restating it, while the code itself measures fine and nothing else flags it. The count
stops at a nested callable, so a closure's narration scores on the closure. A definition
under ten lines reads zero, where one trailing comment alone would be 100%. A docstring
never counts: Python and Julia write one as a string, and every other language attaches
its doc comment beside the definition, never inside it.

The band comes from measurement, since no external guidance gives a comment-percentage
target. The rule is still off by default, and the same measurement is why. A function at
40% has as often been explained as narrated, its comments carrying the constraints a
reader needs. No reading of the syntax separates the two cases. Turn it on with
`[rules] comment_density = true` and set
`[bands] comment_density` to the convention the project keeps. The pattern rule
`banner_comment` names the neighbouring case, a rule of dashes that decorates without
saying anything, and a banner counts toward the density like any other comment.

Each metric is a [rule](@ref "Custom rules"). The set above is the default; a caller
can add their own or opt into rules that are off by default.

Relational (computed across the corpus, not per function): duplicates and opt-in
reimplementation candidates ([Duplicate detection](@ref)), naturalness, within-file
cohesion, and cross-file placement. Naturalness scores each function's token sequence against a
per-language trigram model of the rest of the corpus, in bits per token. The corpus
model is interpolated with a per-file cache model (after Tu et al., "On the Localness
of Software"), so a function is read against its own file's idiom, not just the
corpus's, which sharpens genuine outliers and quiets file-consistent patterns. A
surprising, unidiomatic function scores high, and surprise correlates with bugs.
Reported as `:unnatural` with both scores, the absolute cross-entropy band and the
corpus percentile. A language with too few tokens to model is skipped.

Cohesion asks whether a file's functions group by usage, placement whether a unit sits
in the right file, scattering whether a file's units belong to one module, and
reachability whether a private definition is dead, reported as `:unreferenced`. All four
are in [Cohesion and placement](@ref). The readings taken one level up, over files
depending on files, are in [Dependencies and layout](@ref).
