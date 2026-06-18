# TODO

## Redundant-logic lint pack: deferred rules

Two rules from the lint-pack design were deferred. `duplicate_branches` already
covers the redundant-branch family, and these two need condition-text extraction
that carries more false-positive risk for less marginal value.

- `identical_conditions`: an `if`/`else if` chain that repeats a condition
  (`if (a) ... else if (a) ...`). Needs to extract each arm's condition from the
  chain and compare by normalised text.
- `single_boolean_return`: `if (c) return true else return false`, simplifiable to
  `return c`. Needs `boolean_literal` node types per language and if/else body
  navigation.

## PHP throw is not a control-flow terminator

The old `terminal_types` listed `throw_statement`, which does not exist in
tree-sitter-php (the node is `throw_expression`), so a `throw` never counted as a
terminator. `src/queries/php.scm` preserves that behaviour by omitting it. Consider
tagging `throw_expression` as `@terminal` so `unreachable_after_jump` sees code after
a `throw`. Behaviour change, so out of scope for the query migration.
