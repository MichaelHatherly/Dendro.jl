# Languages and limitations

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

## Registering a language

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
detection, but not `:misplaced`, `:scattered`, `:unreferenced`, or `:back_edge`.

`examples/languages/` in the repository carries a worked Zig query, both files, along with
the reasoning behind the choices a query has to make.

## Limitations

- Ruby swallowed-`rescue` is not flagged. Its handler body is inline rather than
  a block, so it does not fit the detection model.
- Switch `default` adds one to complexity in C, C++, and Java (default shares the
  case node) but not in Go, JavaScript, TypeScript, PHP, or Ruby (default has its
  own node).
- Go empty-body detection is weak: a Go function body always wraps a statement
  list, so empty bodies do not register.
- Metrics are syntactic. Dendro resolves names lexically, within a file and across
  declared `include`/`import`/`export` edges, but never types or dispatch. Concerns
  that need type or dispatch resolution (overload resolution, real call graphs, dead
  code across files) are out of scope.
- Cross-file placement sees only the linkage a language ships a query for, and only
  the include/import edges present in the scanned corpus. A name matching several
  visible definitions is resolved by name, not dispatch, so its weight is split across
  them. Dynamic imports and re-exports are not followed.
