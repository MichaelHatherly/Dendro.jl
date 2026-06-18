; C++ node identification. A `for (auto x : v)` parses as for_range_loop, tagged as
; a decision and a nesting construct like any loop. C++ try has no finally clause,
; so that concept has no pattern.

(function_definition) @function

[(if_statement) (for_statement) (for_range_loop) (while_statement) (do_statement)
 (case_statement) (conditional_expression) (catch_clause)] @decision

[(if_statement) (for_statement) (for_range_loop) (while_statement) (do_statement)
 (switch_statement) (try_statement)] @nesting

["&&" "||"] @short_circuit

(parameter_list) @parameter

(compound_statement) @body

(catch_clause) @catch

(comment) @comment

(identifier) @name

(return_statement) @return

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families.
[(for_statement) (for_range_loop) (while_statement) (do_statement)] @loop
(switch_statement) @switch
(case_statement) @case
(conditional_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (throw_statement)] @terminal
