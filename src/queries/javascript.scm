; JavaScript node identification. The default switch branch has its own node type
; and is excluded from @decision.

[(function_declaration) (function_expression) (arrow_function)
 (method_definition) (generator_function_declaration)] @function

[(if_statement) (for_statement) (for_in_statement) (while_statement)
 (do_statement) (switch_case) (ternary_expression) (catch_clause)] @decision

[(if_statement) (for_statement) (for_in_statement) (while_statement)
 (do_statement) (switch_statement) (try_statement)] @nesting

["&&" "||"] @short_circuit

(formal_parameters) @parameter

(statement_block) @body

(catch_clause) @catch

(comment) @comment

(identifier) @name

(return_statement) @return

(finally_clause) @finally

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

[(return_statement) (break_statement) (continue_statement) (throw_statement)] @terminal
