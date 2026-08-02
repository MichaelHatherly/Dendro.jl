# Languages and limitations

## Languages

bash, c, cpp, go, java, javascript, julia, php, python, ruby, rust, typescript.

JSON and HTML are out of scope: with no functions or control flow, these metrics
do not apply.

## What cross-file resolution reaches per language

Every rule past a single file rests on matching a reference to the definition it names
along declared linkage. How far that reaches differs by language, and where it reaches
nothing the rules go quiet rather than reporting a problem. A quiet report is not the same
as a clean one, so it is worth knowing which case you are in.

Julia, Python, C, Go and Rust resolve normally: a reference names a top-level function, so
both the unit graph and the file graph fill in and every rule applies.

**Java and PHP resolve types, not methods.** A method is reached through a receiver whose
type the resolver never works out, so what one Java or PHP file sees of another is the class
name. The file graph is unaffected and well populated, 1220 edges across Guava's `collect`
package and 304 across Laravel's `Database`, so `:back_edge`, `:dependency_cycle`, `:hub` and
`:split_audience` all work, and so does `:divisible_package`. The *unit* graph carries no
cross-file edge at all, because a class definition is not a function unit, which leaves
`:misplaced`, `:scattered` and `:incoherent_package` silent on a Java or PHP corpus. That is
the type-and-dispatch line holding, not a gap to close: following a method call to its
definition is exactly the resolution Dendro does not do.

**JavaScript resolves ES modules only.** The linkage query reads `import ... from` and
`export`. A corpus written in CommonJS, `require()` and `module.exports`, resolves nothing
across the boundary, so every cross-file rule is silent on it. Express and Lodash are both
in this position.

**Ruby resolves `require_relative` only.** A plain `require` names a file through a load
path the source does not carry, and a method inside a `module` or `class` body is not
spliced into the requiring file's namespace in any case, so a conventionally-written Ruby
library resolves nothing. Sinatra is in this position.

**TypeScript** resolves its ESM output convention, where a specifier names the emitted
`./a.js` and the source on disk is `a.ts`.

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
