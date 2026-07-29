; Dendro's own pattern rules. Adding a language is data, and so is adding a rule: this
; file names shapes the concept vocabulary cannot reach, and `.dendro.toml` says what
; each one means.

; A `catch` that binds no exception discards what went wrong. The second pattern is the
; same pattern made more specific, so it subtracts by node identity; a tree-sitter anchor
; would miss a clause carrying a trailing comment.
(catch_clause) @empty_catch_binding
(catch_clause (identifier)) @empty_catch_binding.not

; An *unnamed* numeric literal. A literal bound to a name is not magic, which is the
; whole point of the rule, so a literal standing as the whole right-hand side of an
; assignment subtracts: `threshold = 7`, `const LIMIT = 13`, and a keyword default
; `f(x = 7)` all name their number and say nothing further. A literal inside a larger
; expression still counts, since `x = 7 + 42` names the result and not the parts.
;
; 0, 1, and 2 are excluded outright: they carry their meaning in the expression around
; them, where 7 or 0.95 is a decision nobody wrote down.
(integer_literal) @magic_number
(float_literal) @magic_number
((integer_literal) @magic_number.not (#any-of? @magic_number.not "0" "1" "2"))
(assignment (operator) . (integer_literal) @magic_number.not)
(assignment (operator) . (float_literal) @magic_number.not)

; A ternary whose own branch is another ternary. Julia writes `?:` without keywords, so a
; chain of them carries its conditions and its results in one line with nothing marking
; where a branch ends. Only a direct child counts: a ternary inside a call inside a branch
; is a separate expression the reader can stop at, where a chain is one thing to hold.
(ternary_expression (ternary_expression)) @nested_ternary

; A parameter annotated with a sized numeric type. Julia compiles a method per argument
; type combination, so narrowing a parameter to `Float64` buys no speed and costs every
; caller holding a `Float32`, a `Rational`, or a unitful quantity. The wider `Real` or
; `Integer` dispatches the same and admits them.
;
; `Int` is absent on purpose: it is the type an integer literal already has, so annotating
; it turns nothing away that a caller was likely to bring.
;
; Anchored inside an `argument_list`, which excludes a struct field, where a concrete type
; is what makes the layout inferable, and a return annotation, which asserts an inference
; result rather than narrowing dispatch.
; fragment: sized_number = "Int8" "Int16" "Int32" "Int64" "Int128" "UInt8" "UInt16" "UInt32" "UInt64" "UInt128" "Float16" "Float32" "Float64"
((argument_list (typed_expression . (identifier) . (identifier) @_t) @concrete_numeric_parameter)
 (#any-of? @_t @sized_number))
((argument_list (assignment . (typed_expression . (identifier) . (identifier) @_t) @concrete_numeric_parameter))
 (#any-of? @_t @sized_number))

; Two splats concatenated into a vector. `[a..., b...]` walks both operands element by
; element to build a result `[a; b]` names directly, and the splat form loses the element
; type where the concatenation keeps it.
(vector_expression (splat_expression) (splat_expression)) @splat_concatenation

; An inlining hint. Julia's compiler decides inlining from the body it can see, so
; `@inline` and `@noinline` overrule that decision and are worth keeping only where a
; benchmark showed the compiler wrong. The annotation reads as a measurement; the rule
; asks for the measurement.
((macrocall_expression (macro_identifier (identifier) @_m)) @manual_inline
 (#any-of? @_m "inline" "noinline"))

; A `const` bound to an empty mutable container. `const` fixes the binding, never the
; contents, so this is a global whose value every method can mutate and, in a threaded
; scan, race on. A container built with entries is a lookup table and says so; one built
; empty exists to be filled later.
((const_statement (assignment (operator) . (call_expression
   (parametrized_type_expression (identifier) @_c)
   (argument_list "(" . ")")))) @mutable_global
 (#any-of? @_c "Dict" "IdDict" "Set" "Vector" "Array"))

; A field access whose object is another field access. Each `.` past the first reaches
; through a value the function was not handed, binding it to the shape of something two
; steps away. Counted per function rather than flagged, since one chain is how a nested
; record is read and a dozen is a missing local.
(field_expression . (field_expression)) @field_chain
