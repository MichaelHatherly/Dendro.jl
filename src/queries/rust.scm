; Rust node identification. Rust has no finally construct, so that concept has no
; pattern. A bare trailing expression is the idiomatic return and has no node, so
; @return tags only an explicit `return`.

(function_item) @function

[(if_expression) (while_expression) (for_expression) (loop_expression)
 (match_arm)] @decision

[(if_expression) (while_expression) (for_expression) (loop_expression)
 (match_expression)] @nesting

["&&" "||"] @short_circuit

(parameters) @parameter

(block) @body

[(line_comment) (block_comment)] @comment

(identifier) @name

(return_expression) @return

(call_expression) @call

(binary_expression) @binary_expr

[(if_expression) (match_expression)] @conditional

; NPath construct families. Rust has no ternary (an `if` expression fills that role)
; or try construct; a match arm is its case body.
[(while_expression) (for_expression) (loop_expression)] @loop
(match_expression) @switch
(match_arm) @case

[(return_expression) (break_expression) (continue_expression)] @terminal
