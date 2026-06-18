; C node identification. C has no finally construct, so that concept has no pattern.

(function_definition) @function

[(if_statement) (for_statement) (while_statement) (do_statement)
 (case_statement) (conditional_expression)] @decision

[(if_statement) (for_statement) (while_statement) (do_statement)
 (switch_statement)] @nesting

["&&" "||"] @short_circuit

(parameter_list) @parameter

(compound_statement) @body

(comment) @comment

(identifier) @name

(return_statement) @return

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families. C has no try construct.
[(for_statement) (while_statement) (do_statement)] @loop
(switch_statement) @switch
(case_statement) @case
(conditional_expression) @ternary

[(return_statement) (break_statement) (continue_statement)] @terminal
