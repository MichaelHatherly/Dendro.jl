# Adopting the new TreeSitter.jl query predicates

Status: proposed
Date: 2026-07-31

Depends on [TreeSitter.jl#65](https://github.com/MichaelHatherly/TreeSitter.jl/pull/65),
which adds nine query predicates. Nothing here can land before that release.

## The problem

A pattern rule is a tree-sitter query, and a query can only ask what its predicates
can ask. Today that is text comparison (`#eq?`, `#match?`, `#any-of?`) plus one
structural question, `#has-ancestor?`, which tests ancestry by node type. Three
kinds of rule fall outside that and have no spelling.

The first is a rule comparing two subtrees. An `elseif` repeating the condition an
earlier branch already took is a dead branch with one right answer, and it is the
shape a generated diff produces. `#eq?` compares raw source, so `x > 0` beside
`x>0` reads as two different conditions. Going the other way, the clone passes hash
subtrees with identifier names and literal values folded out to hold the Type-2
invariant, so they read `x > 0` and `y > 5` as the same, and their floor of ten
named nodes (`DEFAULT_MIN_SIZE`) puts a three-node condition below the index
anyway. Neither end of the existing machinery answers the question.

The second is a rule about what a node is *not* inside, or about which of several
constructs encloses it most closely. `#has-ancestor?` has no negation, and a `.not`
capture cannot stand in: it subtracts by node identity from a shared anchor, which
cannot express "this node has no `let` above it". `#has-ancestor?` also walks to the
root, so a `return` inside a closure inside a function sees both and cannot say
which of the two it returns from.

The third is a rule about a construct at unknown depth below a capture. A query
reaches a descendant only by spelling out the path, so "a `catch` containing no
`rethrow`" or "a loop with no `break`" is unwriteable however the pattern is
arranged.

The consequence is that these rules end up in `rules.jl` as hand-written tree
walks, one per rule, when the query layer is where "languages are data" says they
belong. `flags.jl` already carries `identical_operands` and `duplicate_branches`
for exactly this reason.

## What the release changes

| predicate | what it lets a Dendro rule ask |
|---|---|
| `#structure-eq?` / `#not-structure-eq?` | are these two subtrees the same code, ignoring spacing but not identifiers |
| `#not-has-ancestor?` | is this node outside some construct |
| `#nearest-ancestor?` | which of several constructs encloses this most closely |
| `#ancestor-match?` / `#not-ancestor-match?` | is the enclosing construct of a type named some way |
| `#has-descendant?` / `#not-has-descendant?` | does something of this type sit anywhere below |
| `#not-any-of?` | the negation `#any-of?` was missing |

`#structure-eq?` compares node types, child correspondence, and leaf text.
Whitespace sits between tokens rather than in the tree, so formatting drops out
without being asked; leaf text is compared, so a renamed operand stays a
difference. That lands between raw source text and the clone hash, which is the
comparison a rule about duplicated code wants and neither existing tool provides.

## The edits

Four changes, none of them large, all of them gated on the release.

### 1. Reaching the predicates

Until the release, `Project.toml` carries a `[sources]` table pointing `TreeSitter`
at the `mh/query-predicates` branch. It tracks the branch rather than a commit so
that review of the upstream PR keeps reaching this CI. The compat bound stays at
`"0.2"`, which the branch satisfies since it still declares 0.2.3.

At release the `[sources]` table is deleted and the bound raised. The upstream
`Unreleased` section carries a `Removed` entry (the deprecated timeout and
cancellation-flag parser bindings), so the release is breaking under 0.x semver and
the bound most likely becomes `"0.3"`. Dendro calls none of the removed bindings,
checked by grep over `src/`, so that bump needs no code change of its own. Read the
published version rather than assuming it.

One trap when adopting this locally: `Pkg.instantiate` leaves an existing manifest
alone when it already satisfies the constraints, so a manifest resolved before the
`[sources]` table was added keeps the registry copy and every new predicate reads
as unknown. Delete `Manifest.toml` and instantiate again.

### 2. The predicate allowlist

`PATTERN_PREDICATES` in `src/patterns.jl` exists because TreeSitter.jl warns on an
unknown predicate and then rejects every match, so a query using one reads as clean
code. It gains the nine names, going from 13 entries to 22:

```julia
"not-any-of?", "not-has-ancestor?", "has-descendant?", "not-has-descendant?",
"nearest-ancestor?", "ancestor-match?", "not-ancestor-match?", "structure-eq?",
"not-structure-eq?",
```

The comment above it names TreeSitter.jl 0.2 and says `not-any-of?` and
`not-has-ancestor?` are "the two commonly reached for that do not exist". Both
sentences become wrong and have to move with the code.

The test that pins this behaviour moves with it. `test/patterns.jl` asserts that an
unimplemented predicate is rejected at load, and used `#not-any-of?` as its
example, so it starts passing for the wrong reason the moment that predicate
exists. It needs a name that is genuinely absent, and the positive half of the test
should gain a tree predicate so the new entries are exercised rather than merely
listed.

### 3. The documentation

`docs/src/patterns.md` carries the same claim in its Predicates section: the list
at lines 102-105, and the sentence at 107 saying the two negations "do not exist; a
`.not` capture covers both". That sentence needs replacing rather than deleting,
because the guidance underneath it is still right and now needs stating properly: a
`.not` capture and `#not-has-ancestor?` are different tools. A `.not` capture
subtracts a more specific *shape* from the same anchor, which is how a rule says
"a `catch` binding nothing" or "a `using` with no selected names".
`#not-has-ancestor?` tests *ancestry*, which a shape at a shared anchor cannot
reach. Reach for `.not` when the exclusion is a narrower version of the same
pattern, and for the negated predicate when it is about what encloses the node.

The performance note stays and gains a line. `#has-descendant?` walks the subtree
under a capture, so it costs the size of that subtree per match where the ancestor
predicates cost its depth; a broad capture combined with it is the expensive shape.

### 4. The `unreachable_branch` rule

This is the rule the whole thing is for, and it ships as data rather than as Julia.
An earlier draft of this work was going to add a `@condition` capture to the
concept vocabulary across all twelve language queries and write the rule in
`flags.jl` beside `is_duplicate_branches`. `#structure-eq?` makes that unnecessary:
the rule stays a query, so it stays in the file where a per-language rule belongs
and costs no change to the closed concept vocabulary.

`.dendro.toml`:

```toml
[patterns.unreachable_branch]
message  = "an `elseif` repeating an earlier condition can never run"
severity = "high"
guard    = true
```

`high` because a dead branch is a defect whatever the intent, and `guard` because
Dendro's own source has none, which is the result the rule is written for.

`.dendro/patterns/julia.patterns.scm`:

```scheme
((if_statement . (_) @_c (elseif_clause . (_) @_e)) @unreachable_branch
 (#structure-eq? @_c @_e))
((if_statement (elseif_clause . (_) @_a) (elseif_clause . (_) @_b)) @unreachable_branch
 (#structure-eq? @_a @_b))
```

Two patterns because the pair can be an `if` against its first `elseif` or one
`elseif` against another. Both were run against the branch build of TreeSitter.jl:
each fires exactly one rule capture on the shape it is written for, including the
three-arm case where the second pattern could have produced a match per pair, and
neither fires on three distinct conditions or on a renamed operand.

The fixture in `.dendro/patterns/tests/julia.jl` pins both directions as every rule
there does. The negative cases are the load-bearing half: distinct conditions, a
renamed operand, and a condition respelled with different spacing, which must be
reported since it is the same test written twice and is the case `#eq?` would have
missed. Keep the literals in fixture conditions to 0, 1, or 2, since
`magic_number` excludes those and anything else makes the new fixture fire an
unrelated rule.

## Rules that become writable and should still not ship

Porting a linter's rule set through this work surfaced a set of rules that these
predicates make expressible for the first time. Almost none of them belong here,
and writing that down is the point of this section: the next reader will find them
expressible and should know they were considered.

The bar in `julia.patterns.scm` is that every match has one right answer and it is
a code change. A shape that is merely unusual, or that a reviewer would confirm and
then accept, costs more attention than it returns. Measured against that:

- "an `unsafe_` call outside an `unsafe_`-named function" is now writable with
  `#not-ancestor-match?`, and is a naming convention Dendro does not have. The
  tree-sitter C API is reached through ordinary functions here.
- "a nested function not inside a `let`" is writable with `#has-ancestor?` plus
  `#not-has-ancestor?`. It fires on every closure in the codebase and the fix is a
  performance judgement, not a defect.
- "a `return` whose nearest enclosing function is a closure" is writable with
  `#nearest-ancestor?`. Dendro has one, in `resolve.jl`, and it is correct.
- "a `global` not under `const`" overlaps `global_in_function`, which already
  covers the case that matters.
- The caution rules (`@inbounds`, `ccall`, `finalizer`, `Task`, `@generated`,
  `@threads`, `sleep`) were always writable and always fail the bar. Dendro's own
  source has legitimate instances of several.

`debug_output` is the one that cleared the bar and it needed no new predicate.

## What is still out of reach

Arbitrary predicates. A rule needing to count something, consult a table, or
compare bindings in a way no fixed predicate anticipates cannot be a query, and
that line is deliberate: a query stays data and runs across every grammar, which is
the reason rules are queries here.

Path scoping is unchanged by this work and remains the most valuable thing missing
from the pattern layer. Several rules fail the "one right answer" bar globally but
clear it scoped to `src/`: mutating `ENV`, bare `using`, splatting. Today the only
answer is a `dendro-ignore` at each legitimate site, which by the file's own
standard means the rule should not exist. A `paths` or `exclude` key on
`[patterns.<name>]` would change which rules are admissible at all. It is
independent of the release and could be done first.

## Sequencing

1. Wait for the release. Nothing here works before it.
2. Bump the compat bound and extend `PATTERN_PREDICATES`, with the comment
   correction. This is the whole unblocking change and can land alone.
3. Correct `docs/src/patterns.md`, including the `.not` guidance.
4. Add `unreachable_branch`: config entry, both query patterns, fixtures. The
   dogfood item asserts `check_patterns` agrees with the fixture, that
   `errors(src)` is empty, and that no declared rule is unmatched, which a guard is
   exempt from.

Steps 2 and 3 are one commit. Step 4 is a second.

## Deliberately not in this

Moving existing `rules.jl` flag rules into the query layer. `#has-descendant?`
would let `return_in_finally` and parts of `empty_catch` become queries, but they
work, they are tested, and rewriting a working rule to use a newer mechanism is
churn with a regression risk and no finding behind it. The reason `rules.jl` holds
the rules needing a binding or a tree walk does not stop being true because one
more thing became expressible.

Adding a `@condition` capture to the concept vocabulary. It was the plan before
`#structure-eq?` existed and is now unnecessary for this rule. Should a later
metric need to read a conditional's test rather than compare two of them, the case
should be made on that metric's own terms.
