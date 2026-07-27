# Registering a language Dendro does not ship

Dendro's built-in languages are a query, a `PROFILES` entry, and an extension entry. A
project can add its own the same way from a `.dendro.toml`, without patching the package:

```toml
[languages.zig]
extensions = ["zig"]
grammar = "/path/to/tree-sitter-zig"
queries = "/path/to/dendro-queries"
```

- `queries` is the only required key. It names a directory holding `<name>.scm`, the
  node-identification query, and optionally `<name>.scopes.scm` and `<name>.imports.scm`.
- `grammar` defaults to the language name, resolved to `tree_sitter_<name>_jll`. Point it
  at a directory instead to load a local grammar repository, which needs a
  `tree-sitter.json` and a built shared library beside it.
- `extensions` are the file types the language claims, with or without a leading dot.
  Omit them to keep whatever the built-in table already maps for that name.

A registered language of the same name as a built-in replaces it, which is how a project
retunes a shipped query without a fork:

```toml
[languages.python]
queries = "my-queries"
```

## What each query gets you

Only `<name>.scm` is required, and it carries the scalar metrics, the structural flags,
and duplicate detection. The companions are separate steps:

| Query | Adds |
|---|---|
| `<name>.scm` | metrics, flags, exact and near-miss clones |
| `<name>.scopes.scm` | lexical bindings, so `:low_cohesion`, `unused_parameter`, `unused_local`, `shadowed_variable`, and `local_count` score |
| `<name>.imports.scm` | cross-file edges, so `:misplaced`, `:scattered`, `:unreferenced` score |

A language with no scopes or imports query is skipped by those passes rather than scored
wrongly by them. Write the scopes query rather than leaving it out: without one a language
loses cohesion and every binding-based flag, which is a large share of what Dendro is for.

Cross-file resolution needs more than the query. A `LINKAGES` entry is Julia code in the
package, so a config-registered language reaches the per-file passes and clone detection
but not the cross-file ones.

## Worked example: Zig

`zig/` carries both queries for
[tree-sitter-zig](https://github.com/tree-sitter-grammars/tree-sitter-zig): `zig.scm` for
node identification and `zig.scopes.scm` for lexical scopes. Zig has no grammar JLL in the
General registry, so it is the case a local grammar directory exists for: build one and
point `grammar` at the checkout.

```bash
git clone https://github.com/tree-sitter-grammars/tree-sitter-zig
cd tree-sitter-zig && tree-sitter build     # emits zig.dylib / zig.so
```

```toml
[languages.zig]
extensions = ["zig"]
grammar = "/path/to/tree-sitter-zig"
queries = "/path/to/Dendro.jl/examples/languages/zig"
```

Being an example rather than a shipped language, it is not covered by the test suite: the
suite would have to build a grammar to run it. Treat the query as a starting point to read
and adjust, not as a supported surface.

### Choices the Zig query makes

The query comments carry the reasoning; two are worth stating up front, since both shape
how complex Zig code scores.

`try` is not a decision point. It forwards an error rather than choosing between paths,
and Zig code uses it on nearly every fallible call, so counting it would swamp the metric.
This is the call Dendro already makes for Rust's `?`. `catch` and `orelse` do count: each
names an alternative value or block.

Builtins (`@import`, `@intCast`) are not tagged as calls. They are compile-time builtins
rather than calls into the program, and `@import` alone would dominate every file's callee
vocabulary.

The scopes query binds only a `variable_declaration` that carries its `const` or `var`
keyword. The grammar leaves that keyword optional, so a bare `total = 9;` parses as a
`variable_declaration` too, and matching every one of them would read a rebinding as a
fresh definition and stop the assigned name counting as a use. This is the same split
Julia's scopes query makes for the same reason.

### Not covered

A `test { ... }` block is a scope, so its locals do not leak, but it is not tagged as a
unit and its body is not measured. Zig names tests with a string literal rather than an
identifier, so there is no unit name to report against.

Cross-file linkage. Zig's `@import("foo.zig")` is a relative-path splice that Dendro's
existing `splice_resolve` would handle, and `pub` maps onto `modifier_public`, but a
`LINKAGES` entry is Julia code in the package rather than config, so the cross-file passes
skip Zig for now.
