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
