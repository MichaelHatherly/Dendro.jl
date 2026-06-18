; Julia node identification. Each pattern tags a construct Dendro measures with a
; capture naming the concept. A short-form `f(x) = expr` is an assignment whose
; left side resolves to a call signature, possibly through `::T` / `where` wrappers,
; so each wrapper combination is an explicit pattern anchored to the assignment's
; first child.

(function_definition) @function
(assignment . (call_expression)) @function @short_function
(assignment . (typed_expression . (call_expression))) @function @short_function
(assignment . (where_expression . (call_expression))) @function @short_function
(assignment . (where_expression . (typed_expression . (call_expression)))) @function @short_function
(assignment . (typed_expression . (where_expression . (call_expression)))) @function @short_function

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

(if_statement) @conditional

[(return_statement) (break_statement) (continue_statement)] @terminal
