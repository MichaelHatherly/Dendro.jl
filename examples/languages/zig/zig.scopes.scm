; Zig lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function names
; hoist to the enclosing scope so a sibling reference resolves; a container body is a
; scope so its methods hoist into it. Parameters are not captured: they form no
; cross-function cohesion edge. Without this query Zig would lose cohesion scoring and
; the unused-parameter flag, both of which read references.

; --- Scope regions ---
; Zig's containers are expressions (`const Foo = struct { ... }`), so the scope is the
; container body rather than the declaration that names it.
(source_file) @scope
(function_declaration) @scope
(struct_declaration) @scope
(enum_declaration) @scope
(union_declaration) @scope
(opaque_declaration) @scope
(test_declaration) @scope

; --- Function names (hoisted) ---
(function_declaration name: (identifier) @definition.function)

; --- Local bindings ---
; The grammar's `variable_declaration` keeps its `const`/`var` keyword optional, so a bare
; `total = 9;` and `total += x;` parse as one too. Requiring the keyword is what separates
; a fresh binding from a rebinding: matching every `variable_declaration` would read an
; assignment as a definition, and the assigned name would stop counting as a use of the
; variable it rebinds. The name is the child right after the keyword rather than a `name:`
; field, so the pattern is anchored there to avoid matching the initializer's identifiers.
;
; Container-level and function-local declarations share the node type, and both are tagged
; `local` so neither hoists: geometric scoping already places a top-level declaration in
; the file scope, while hoisting a function-local `const` would wrongly lift it to file
; visibility.
(variable_declaration "const" . (identifier) @definition.local)
(variable_declaration "var" . (identifier) @definition.local)

; A captured payload binds a name for the body that follows it: `for (xs) |x|`,
; `if (opt) |v|`, `while (it.next()) |n|`, `catch |err|`.
(payload (identifier) @definition.local)

; --- References ---
; A `builtin_identifier` (`@import`) is deliberately absent: it names a compile-time
; builtin, not a program name that could resolve to a definition. A field access carries
; its member as a plain `identifier`, so `std.mem.eql` reads as three references and only
; `std` resolves; the other two match no definition and stay unbound, as Go's
; `field_identifier` references do.
(identifier) @reference

; A container field is not captured as a definition, matching every built-in language:
; two methods touching one field are not linked by cohesion. Capturing it would make
; Zig's cohesion scores incomparable to the rest of a mixed corpus.
