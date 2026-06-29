; JavaScript node identification. The default switch branch has its own node type
; and is excluded from @decision.

[(function_declaration) (function_expression) (arrow_function)
 (method_definition) (generator_function_declaration)] @function

; A concise arrow `x => expr` has an expression body, not a statement block. Marking
; the arrow short-form routes `function_body` to that expression, which always does
; work, so a concise arrow never reads as an empty body. A block-bodied arrow keeps
; its `@body` block and is unaffected.
(arrow_function) @short_function

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

; Name a unit by its defining name, not the first identifier the lexical scan
; reaches: an arrow callback is otherwise labelled by its first parameter. A bare
; anonymous arrow stays unnamed.
(function_declaration name: (identifier) @def_name)
(method_definition name: (property_identifier) @def_name)
(variable_declarator name: (identifier) @def_name value: (arrow_function))

(return_statement) @return

(finally_clause) @finally

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families.
[(for_statement) (for_in_statement) (while_statement) (do_statement)] @loop
(switch_statement) @switch
[(switch_case) (switch_default)] @case
(ternary_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (throw_statement)] @terminal
