# Pattern query syntax

```@meta
CurrentModule = Dendro
```

What a `<lang>.patterns.scm` file may contain: how a capture names a rule, which
predicates are available, and how a repeated shape factors out. [Pattern rules](@ref)
covers declaring a rule, testing one, and what the mechanism cannot reach.

## Captures

```scheme
; A capture names a rule.
(catch_clause) @empty_catch_binding

; A `.not` capture subtracts from the rule of the same name, by node identity. Write
; the pattern, then the more specific pattern that should be excluded.
(catch_clause (identifier)) @empty_catch_binding.not

; A `_` prefix marks a capture a predicate needed, never a rule of its own.
((call_expression (identifier) @_f) @eval_call (#eq? @_f "eval"))
```

Three conventions carried by the capture name:

- `@rule` is a match to report.
- `@rule.not` subtracts from `@rule` by node identity. Because the two patterns land on
  the same anchor node, negation is predictable and does not depend on where inside a
  match the exclusion sat. This is how a rule says "without": a `catch` binding nothing, a
  `switch` with no default, a function with no return type annotation.
- `@_anything` is a helper. A predicate has to reference a capture, so `#eq? @_f "eval"`
  forces capturing the identifier it tests; without the prefix that capture would become a
  rule firing on every node the predicate examined.

Several patterns may share one capture name and accumulate, which is how one rule carries
more than one spelling:

```scheme
((call_expression function: (member_expression object: (identifier) @_o))
 @debug_output (#eq? @_o "console"))
(debugger_statement) @debug_output
```

Every other capture must have a `[patterns.<name>]` table. A capture naming no declared
rule is an error at load, which is what catches a typo and a helper that lost its
underscore.

## Predicates

The predicates available are the ones TreeSitter.jl implements. Anything else is rejected
when the rule loads.

Reading capture text: `#eq?`, `#not-eq?`, `#any-of?`, `#not-any-of?`, `#match?`,
`#not-match?`, and the quantified `#any-eq?`, `#any-not-eq?`, `#any-match?`,
`#any-not-match?`.

Reading the tree around a capture: `#has-ancestor?` and `#not-has-ancestor?` for whether
some construct encloses the node, `#nearest-ancestor?` for which of several encloses it
most closely, `#ancestor-match?` and `#not-ancestor-match?` for whether the enclosing
construct's own text matches a pattern, and `#has-descendant?` and `#not-has-descendant?`
for whether something sits anywhere below it.

Comparing two captures as code: `#structure-eq?` and `#not-structure-eq?` compare node
types, child correspondence, and leaf text. Whitespace lives between tokens rather than in
the tree, so formatting drops out; leaf text is compared, so a renamed operand stays a
difference. That is the comparison a rule about duplicated code wants, where `#eq?` reads
raw source and the clone passes fold identifiers out of their hashes entirely.

Node properties and metadata: `#is?`, `#is-not?`, and `#set!`.

A `.not` capture and a negated predicate are different tools. `.not` subtracts a narrower
*shape* from the same anchor, which is how a rule says "a `catch` binding nothing" or "a
`using` with no selected names". A negated predicate asks about what encloses the node or
sits below it, which no shape at a shared anchor reaches. Reach for `.not` when the
exclusion is a more specific version of the same pattern, and for the predicate otherwise.

Prefer `#eq?` and `#any-of?` to `#match?` where either works, since a match's predicates
are re-evaluated once per capture and a regex rule reruns it each time. `#has-descendant?`
walks the subtree under a capture, so it costs the size of that subtree per match where
the ancestor predicates cost its depth; a broad capture paired with it is the expensive
shape.

## Fragments

A shape repeated across rules factors out. A `; fragment:` comment defines a piece of
query text and a reference splices it:

```scheme
; fragment: loops = [(while_statement) (for_statement)]

@loops @any_loop
(function_definition (block @loops)) @loop_in_function
```

Expansion is one level: a reference inside a fragment is left alone rather than expanded
recursively. A fragment cannot share a name with a declared rule, since a capture cannot
be both a shape to splice and a rule to report.

