# Pattern rules

```@meta
CurrentModule = Dendro
```

A [`Rule`](@ref) measures the concept vocabulary a language's `<lang>.scm` query
produces: decision points, nesting, catch clauses, parameters. That vocabulary is closed
on purpose, since it is what keeps metric code free of grammar node types. It also means
a rule cannot name a shape Dendro has no concept for.

A pattern rule can. It is a second query family, `<lang>.patterns.scm`, where a capture
names a *rule* instead of a concept. The set of names is open and the queries are written
against concrete grammar node types deliberately, because being language-specific is the
point.

## Declaring a rule

A rule is declared once, language-independently, in `.dendro.toml`:

```toml
[patterns.empty_catch_binding]
message  = "`catch` with no exception binding discards the error"
severity = "high"

[patterns.magic_number]
message = "unnamed numeric literals in one function"
kind    = "scalar"
band    = [5, 10]
```

| key | |
| --- | --- |
| `message` | required; what the rule says when it fires |
| `severity` | `"warn"` (default) or `"high"`, for a flag rule |
| `kind` | `"flag"` (default) or `"scalar"` |
| `band` | required by a scalar, rejected on a flag; must start at 1 or higher |
| `guard` | `false` (default); `true` when matching nothing is the wanted state |

`severity` defaults to `warn` because [`errors`](@ref) gates on the `:high` band. A rule
that fires across a corpus would otherwise make the gate unsatisfiable the day it is
written. Promoting one to `high` is a line of config and the project's call.

A scalar's band starts at 1 or higher so that a unit with no matches scores `:ok`. A band
starting at zero would report every function in the corpus for containing nothing.

Metadata lives here and never beside the queries. A rule name is language-independent and
a query is not, so a message kept next to a query would be either per language and free to
drift, or in a second config file with a second cascade to merge. A pattern rule also
toggles off through `[rules]` by the same name a built-in does:

```toml
[rules]
magic_number = false
```

## Writing the query

Queries live in `.dendro/patterns/<lang>.patterns.scm` beside the config, and in
`~/.config/dendro/patterns/` for rules shared across repositories. Both locations are
read and compose; where both define the same rule for the same language, the repo's wins
for that pair.

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

### Predicates

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

### Fragments

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

### One rule in two grammars

A rule declared once and realised twice is what the split between the declaration and the
queries is for. `optional_equality` catches `x == nothing` in Julia and `x == None` in
Python, and the two queries look nothing alike:

```scheme
; julia.patterns.scm
((binary_expression (operator) @_op (identifier) @_n) @optional_equality
 (#eq? @_op "==") (#eq? @_n "nothing"))
((binary_expression (identifier) @_n (operator) @_op) @optional_equality
 (#eq? @_op "==") (#eq? @_n "nothing"))
```

```scheme
; python.patterns.scm
((comparison_operator "==" (none)) @optional_equality)
```

Python keeps the operator in `comparison_operator` as an anonymous token, so one pattern
covers both operand orders. Julia makes it a named child, and sibling patterns match in
source order, so each order needs its own pattern. The message the finding carries is
declared once for both.

Where a query cannot resolve a name it reads convention instead, and both languages need
the same carve-out for it: `typeof(x) == typeof(y)` and `type(x) == type(y)` compare two
types that arrived as values, which `==` answers correctly. A capitalised right operand is
what separates those from a comparison against a type written down.

Fixtures are where a query's disagreements with a grammar get recorded, and a rule written
against an operator has one waiting: `x!==nothing` without spaces parses as the identifier
`x!` and the operator `==`, so correct Julia reads as the shape the rule looks for. A `.not`
pattern reading the left operand is what excludes it, and a fixture line is what keeps the
exclusion from being deleted later as dead weight.

## Flag rules and scalar rules

A flag rule reports one finding per matched node, carrying its declared severity as the
absolute band. A scalar rule counts its matches per unit and is scored against its band
and the corpus percentile, exactly as `cyclomatic` is, including retuning through
`[bands]`:

```toml
[bands]
magic_number = [3, 6]
```

A scalar counts through the same fold every built-in scalar uses, so it stops at nested
callables: a closure's matches belong to the closure, not to the function around it.

Because a pattern rule resolves to an ordinary [`Rule`](@ref), everything else follows
with no special handling. Findings carry `dendro-ignore` suppression by rule name, scope
to a diff under `analyze`'s `base`, reach [`errors`](@ref) when their band is `:high`, and
participate in the ratchet under `errors(paths; since)`.

## When a rule is wrong, it says so

A rule that reports nothing reads as clean code, which is the failure this design works
hardest to prevent. Every way of getting a rule wrong is loud.

Tree-sitter validates a query when it compiles, so a node type the grammar does not have,
an unknown field, a capture reference no pattern binds, and a syntax error all fail at
load, naming the file and the line:

```
dendro: node type error at line 3 of .dendro/patterns/julia.patterns.scm
```

A predicate TreeSitter.jl does not implement compiles cleanly and then rejects every
match, so it is rejected at load instead, with the alternatives named. A capture naming no
declared rule is an error, and so is a fragment sharing a rule's name. An error inside an
expanded fragment names the fragment, where it was defined, and where it was used, rather
than an offset into text nobody wrote.

The one case none of that reaches is a well-formed query naming a shape that simply never
occurs. A rule that matched nothing anywhere in the corpus is reported after the scan:

```
warning: pattern rule(s) matched nothing: no_such_shape
```

### Guard rules

Most rules worth writing are silent on a codebase that is already clean, and that silence is
the result they were written for. It reads identically to the broken rule above, so the
declaration is what tells them apart:

```toml
[patterns.nothing_equality]
message = "`== nothing` compares where `=== nothing` identifies"
guard   = true
```

A guard is never reported as unmatched. It is not switched off: write the shape and the
finding arrives as it would from any other rule. Reach for it when the rule names something
the project has decided never to write, and leave it off when the rule is meant to find
something and you want to hear that it did not.

## Testing a rule

Those catch a rule that is malformed, not one that fires on the wrong thing. Fixtures pin
both directions. They live in a `tests/` folder beside the queries, one file per language,
and mark the lines a rule must match:

```julia
# .dendro/patterns/tests/julia.jl
try r() catch    # dendro-expect: empty_catch_binding
end
try r() catch e  # unmarked, so the rule must not fire here
end
```

```
$ dendro --check-patterns src/
```

A marked line the rule missed is a failure, and so is an unmarked line it matched.
Checking for false positives is the point: a check that only asked whether a rule matched
something would pass a rule that matched everything.

A fixture records what the *query* matched, for either kind of rule. A scalar rule's band
and percentile are Dendro's own scoring and are tested elsewhere, so a scalar fixture
marks the lines its occurrences sit on exactly as a flag fixture does.

A rule with no fixture is not a failure. Requiring one would be friction on writing a
two-line house rule, and the zero-match report already covers the rule that never fires.

[`check_patterns`](@ref) is the same check from Julia, returning a
[`PatternTestFailure`](@ref) per disagreement, so a project can assert on it in its own
suite.

## What a pattern rule cannot do

A query reads a node's shape, its text, and its ancestry. It cannot see bindings and it
cannot resolve a type, which is the same line every other part of Dendro holds.

A rule needing either stays a Julia [`Rule`](@ref) passed to [`analyze`](@ref)'s `rules`,
described under [Custom rules](rules.md). That path is reachable from Julia but never from
a config file: loading Julia named by a repo's `.dendro.toml` would execute it during a
scan.

Measured against the default rule sets of Clippy, Ruff, and ESLint, roughly half of a
sampled 150 rules are expressible as pattern rules. The remainder needs types or trait
resolution (about a sixth), is formatting and node ordering (about a quarter), needs
binding resolution (a twentieth), or is something Dendro already reports. The fit is best
for Python, at around 70%, and weakest for Rust, at 44%, where linting resolves traits.
