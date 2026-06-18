; Python node identification. Each pattern tags a construct Dendro measures with a
; capture naming the concept.

(function_definition) @function

[(if_statement) (elif_clause) (for_statement) (while_statement)
 (except_clause) (conditional_expression)] @decision

(elif_clause) @continuation

[(if_statement) (for_statement) (while_statement) (try_statement)
 (with_statement)] @nesting

; `and` and `or` are anonymous keyword tokens.
["and" "or"] @short_circuit

(parameters) @parameter

(block) @body

(except_clause) @catch

(comment) @comment

(identifier) @name

(pass_statement) @trivial_body

(return_statement) @return

(finally_clause) @finally

(call) @call

[(comparison_operator) (boolean_operator) (binary_operator)] @binary_expr

[(if_statement) (match_statement)] @conditional

[(return_statement) (break_statement) (continue_statement) (raise_statement)] @terminal
