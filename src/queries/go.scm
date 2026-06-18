; Go node identification. Go has no finally construct, so that concept has no
; pattern. The default switch branch has its own node type and is excluded from
; @decision.

[(function_declaration) (method_declaration)] @function

[(if_statement) (for_statement) (expression_case) (type_case)
 (communication_case)] @decision

[(if_statement) (for_statement) (expression_switch_statement)
 (type_switch_statement) (select_statement)] @nesting

["&&" "||"] @short_circuit

(parameter_list) @parameter

(block) @body

(comment) @comment

(identifier) @name

(return_statement) @return

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (expression_switch_statement) (type_switch_statement)] @conditional

[(return_statement) (break_statement) (continue_statement)] @terminal
