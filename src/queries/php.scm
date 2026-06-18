; PHP node identification. The default switch branch has its own node type and is
; excluded from @decision.

[(function_definition) (method_declaration)] @function

[(if_statement) (else_if_clause) (for_statement) (foreach_statement)
 (while_statement) (do_statement) (case_statement) (conditional_expression)
 (catch_clause)] @decision

(else_if_clause) @continuation

[(if_statement) (for_statement) (foreach_statement) (while_statement)
 (do_statement) (switch_statement) (try_statement)] @nesting

["&&" "||" "and" "or"] @short_circuit

(formal_parameters) @parameter

(compound_statement) @body

(catch_clause) @catch

(comment) @comment

(name) @name

(return_statement) @return

(finally_clause) @finally

(function_call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

[(return_statement) (break_statement) (continue_statement)] @terminal

; `throw` is an expression wrapped in a statement; tag the statement so code after
; it in the same block reads as unreachable.
(expression_statement (throw_expression)) @terminal
