; Julia node identification. Each pattern tags a construct Dendro measures with a
; capture naming the concept. A short-form `f(x) = expr` is an assignment whose
; left side resolves to a call signature, possibly through `::T` / `where` wrappers,
; so each wrapper combination is an explicit pattern anchored to the assignment's
; first child.

; A `function … end` delimits its body with the construct, so an empty one is an empty
; body, not a declaration; @requires_body marks that for `empty_body`.
(function_definition) @function @requires_body
(assignment . (call_expression)) @function @short_function
(assignment . (typed_expression . (call_expression))) @function @short_function
(assignment . (where_expression . (call_expression))) @function @short_function
(assignment . (where_expression . (typed_expression . (call_expression)))) @function @short_function
(assignment . (typed_expression . (where_expression . (call_expression)))) @function @short_function

; A qualified definition `Module.method(...)` names the unit by its final
; component, not the module the lexical scan would reach first. Capture the field
; identifier of the call target's `field_expression`, across the same signature and
; short-form shapes the `@function` patterns enumerate.
(function_definition (signature (call_expression . (field_expression (_) (identifier) @def_name))))
(function_definition (signature (where_expression (call_expression . (field_expression (_) (identifier) @def_name)))))
(assignment . (call_expression . (field_expression (_) (identifier) @def_name)))
(assignment . (typed_expression . (call_expression . (field_expression (_) (identifier) @def_name))))
(assignment . (where_expression . (call_expression . (field_expression (_) (identifier) @def_name))))
(assignment . (where_expression . (typed_expression . (call_expression . (field_expression (_) (identifier) @def_name)))))
(assignment . (typed_expression . (where_expression . (call_expression . (field_expression (_) (identifier) @def_name)))))

[(if_statement) (elseif_clause) (for_statement) (while_statement)
 (ternary_expression) (catch_clause)] @decision

(elseif_clause) @continuation

[(if_statement) (for_statement) (while_statement) (try_statement)] @nesting

; `&&` and `||` are named (operator) nodes, distinguished only by text.
((operator) @short_circuit (#any-of? @short_circuit "&&" "||"))

(argument_list) @parameter

(block) @body

(catch_clause) @catch

[(line_comment) (block_comment)] @comment

(identifier) @name

(return_statement) @return

(finally_clause) @finally

(call_expression) @call

(binary_expression) @binary_expr

; Julia spells a binary operator as a named child of the expression, unlike the
; other grammars where it is anonymous. Tag it so operand-counting can exclude it.
(binary_expression (operator) @operator)

(if_statement) @conditional

; NPath dispatches on construct family. Julia has no switch.
[(for_statement) (while_statement)] @loop
(ternary_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement)] @terminal
