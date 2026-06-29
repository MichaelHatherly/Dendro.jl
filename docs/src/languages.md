# Languages and limitations

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

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
