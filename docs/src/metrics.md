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

A percentile ranks against whatever the scan parsed, so a checked-in bundle left in the
corpus decides the ranks. Its few thousand minified helpers become the sample
`(javascript, cyclomatic)` is measured against, and nothing anyone wrote ranks near the top
again. Clone detection reads the same corpus, where a bundle repeats its helpers often
enough to fire `:duplicate` at the error band on code nobody can edit. Dendro turns such a
file away before parsing, by its path through `ignore` or by its head through `generated`,
and closes the report with a line saying how many went. [Configuration file](@ref) covers
both keys.

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

## Corpus scores

Every reading above names a site. The two scores here name none: each is one ratio over the
whole corpus, printed after the last finding and nowhere else.

```
erosion   0.16
verbosity 0.03
```

Erosion is the share of a codebase's callable weight sitting in complex functions. A
definition's weight is its cyclomatic complexity times the square root of its length, and
erosion is the weight in definitions past complexity 10 over the weight in all of them. The
cut comes from SlopCodeBench, which takes it from Radon. It coincides with `cyclomatic`'s
own warn edge, so the two agree by construction: the rule says which functions sit past the
edge, and erosion says how much of the codebase they are.

Verbosity is the share of source lines a finding covers. The numerator is every line a
declared flag rule matched or a `:duplicate` or `:near_duplicate` finding spans, counted
once however many findings reach it; the denominator is the corpus's physical lines. Only
declared rules count, the pack Dendro ships plus whatever a project adds, since that is the
population SlopCodeBench measures. Built-in flags are out, and so is a scalar pattern rule:
a scalar counts matches per unit and names no region. A suppressed match still counts, since
a `dendro-ignore` accepts a finding where this measures what the source holds.

Both read the whole corpus even under `--base`. A diff narrows which findings get reported;
it cannot narrow the codebase a ratio is taken over. That corpus is the scanned one after
`ignore` and `generated` have dropped what they drop, so verbosity divides by the lines
Dendro parsed rather than by every line in the tree.

### Reading them against a base ref

With a `base` ref the same scores are taken over the corpus as it stood there, so each line
says what it was and which way it moved. A third line says how large the change was:

```
erosion   0.42  (base 0.39, +0.03)
verbosity 0.19  (base 0.21, -0.02)
lines     +412 -118  (net +294)
```

The line counts are libgit2's own tally over the diff, restricted to the source the scan
covers: a path under a scanned root, with an extension a language profile claims, surviving
`ignore`. Those are the paths the scan would have parsed. A file the change deleted is in no
corpus, and its lines still reach the removed count, which is what lets a net go negative.
Two consequences follow from reading git instead of the parsed files. Rename detection is
off, so a rename reads as a deletion plus an addition. A binary or unparseable file falls
out on its extension, which is also what keeps a vendored asset out of the count.

Scoring the base costs a second pass over the base tree, roughly half again the time of a
`--base` scan. That pass rebuilds only what the two ratios read: the corpus, its parse, and
the two clone passes.
On a large corpus, set `[report] base_summary = false` when that cost outweighs the base
comparison; the current scores and line delta remain.

### What the numbers are not

SlopCodeBench's Table 2 measured Python two ways:

| | verbosity | erosion |
| --- | --- | --- |
| human-written | 0.15 ± 0.06 | 0.31 ± 0.17 |
| agent-written | 0.33 ± 0.10 | 0.68 ± 0.20 |

Dendro never prints those beside your own, because they are a population and never a
threshold.

They are not comparable. Verbosity's numerator here is whichever rules you have enabled,
where the paper counts a fixed set of eight Python rules; the shipped pack is fifteen flags
across twelve languages, and a project adding its own moves the number again. Erosion pools
every language in the corpus, where the paper measured Python alone.

The value is the trend against yourself. A ratio over a corpus names no site, so it names no
edit, and no one commit can satisfy it. That is why neither is a finding, neither carries a
band or a percentile, and neither reaches [`errors`](@ref).
