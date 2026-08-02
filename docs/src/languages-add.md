# Adding a language

The languages Dendro ships queries for are listed under
[Languages and limitations](@ref), along with how far cross-file resolution reaches in
each.

Adding a language is a tree-sitter query, a profile entry, and an extension entry. A
project supplies all three from its `.dendro.toml`, so a language Dendro does not ship
needs no fork:

```toml
[languages.zig]
extensions = ["zig"]
grammar = "/path/to/tree-sitter-zig"
queries = "/path/to/my-queries"
```

`queries` is the only required key, naming a directory that holds `<name>.scm` and
optionally `<name>.scopes.scm` and `<name>.imports.scm`. `grammar` defaults to the
language name and resolves to `tree_sitter_<name>_jll`; point it at a directory instead
to load a grammar from a local tree-sitter repository, which needs a `tree-sitter.json`
and a built shared library beside it. That is the only route for a grammar with no JLL in
the General registry. `extensions` are the file types the language claims, with or without
a leading dot; omit them to keep whatever the built-in table already maps for that name.

A registered language of the same name as a built-in replaces it, which is how a project
retunes a shipped query without a fork:

```toml
[languages.python]
queries = "my-queries"
```

Write the scopes query rather than leaving it out. Without one the language loses
cohesion scoring and every binding-based flag (`unused_parameter`, `unused_local`,
`shadowed_variable`, `local_count`), which is a large share of what Dendro reports. The
passes skip a language that ships no scopes query rather than scoring it wrongly.

Cross-file resolution needs more than a query: a linkage entry is Julia code in the
package, so a registered language reaches the per-file metrics, the flags, and clone
detection, but none of the passes built on cross-file references: `:misplaced`,
`:scattered`, `:unreferenced`, `:split_audience`, `:back_edge`, `:dependency_cycle`,
`:hub`, `:incoherent_package`, or `:divisible_package`.

## Choices a query has to make

The concept vocabulary is closed and a grammar's node types are not, so writing a query
means deciding which of a language's constructs answer to each concept. Three of those
decisions recur, stated here against Zig, where each one came up.

Not every error construct is a decision point. Zig's `try` forwards an error rather than
choosing between paths, and idiomatic code writes it on nearly every fallible call, so
counting it would swamp the metric. `catch` and `orelse` do count, since each names an
alternative value or block. The shipped Rust query makes the same call for `?`.

Compile-time builtins are not calls. Zig's `@import` and `@intCast` do not call into the
program, and `@import` alone would dominate every file's callee vocabulary, which is what
the reimplementation pass reads.

A scopes query binds a declaration, not an assignment. Zig's grammar leaves the `const` or
`var` keyword optional, so a bare `total = 9;` parses as a `variable_declaration` too, and
matching every one of those reads a rebinding as a fresh definition and stops the assigned
name from counting as a use. Julia's scopes query makes the same split for the same reason.
