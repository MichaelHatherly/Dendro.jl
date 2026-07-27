; Zig node identification, written against tree-sitter-grammars/tree-sitter-zig. An
; example of a language registered from a `.dendro.toml` rather than shipped: Zig has no
; grammar JLL in the General registry, so its grammar is built from a local checkout.
;
; The grammar splits most control constructs into a statement and an expression form
; (`if_statement`/`if_expression`), since Zig lets either appear where a value is wanted.
; Both forms are tagged everywhere, so `const x = if (c) a else b` measures like the
; statement it mirrors.

(function_declaration) @function

; `switch_case` covers every arm including `else =>`, so the default branch adds one, the
; same variance C, C++, and Java carry. `catch_expression` is a handler with an
; alternative value, so it branches; `orelse` is the same for an optional. `try` is not
; tagged: it forwards an error rather than choosing between paths, and counting Zig's
; pervasive `try` would swamp the metric, the same call Dendro makes for Rust's `?`.
[(if_statement) (if_expression) (if_type_expression)
 (while_statement) (while_expression)
 (for_statement) (for_expression)
 (switch_case) (catch_expression)] @decision

["orelse"] @decision

; An `else if` nests an `if_statement` inside the `else_clause` rather than getting its
; own clause node, so there is no continuation to tag and a chain reads as nested. Rust,
; Go, C, and Java share that shape and that variance.
[(if_statement) (if_expression) (if_type_expression)
 (while_statement) (while_expression)
 (for_statement) (for_expression)
 (switch_expression)] @nesting

; `and` and `or` are anonymous operator tokens. `orelse` is short-circuiting too but is
; not boolean, so it stays out of the boolean complexity count.
["and" "or"] @short_circuit

(parameters) @parameter

; A parameter's name identifier. An anonymous parameter (`_: u32`) and a `comptime`-only
; type parameter introduce no simple name and are not tagged.
(parameters (parameter name: (identifier) @parameter_name))

(block) @body

; Only a block-bodied `catch` is a handler that can be empty. `catch return err` and
; `catch 0` handle the error with an expression and have no block child, so they are not
; tagged: an absent body reads as a swallowed error, which for those two is wrong.
(catch_expression (block)) @catch

(comment) @comment

(identifier) @name

(return_expression) @return

(call_expression) @call

; A call's target name: a plain identifier, or a field call's member name (`std.mem.eql`
; counts as `eql`). A `builtin_function` (`@import`, `@intCast`) is not tagged as a call:
; it is a compile-time builtin rather than a call into the program, and `@import` alone
; would dominate every Zig file's callee vocabulary.
(call_expression function: (identifier) @callee)
(call_expression function: (field_expression member: (identifier) @callee))

(binary_expression) @binary_expr

[(if_statement) (if_expression) (if_type_expression) (switch_expression)] @conditional

; NPath construct families. Zig has no ternary: `if` as an expression fills that role and
; is already counted as a conditional. A `switch_case` is its own case body.
[(while_statement) (while_expression) (for_statement) (for_expression)] @loop
(switch_expression) @switch
(switch_case) @case

[(return_expression) (break_expression) (continue_expression)] @terminal
