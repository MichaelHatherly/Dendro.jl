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

; A parameter's name identifier, covering a grouped declaration's every name and
; the variadic form. The method receiver is a parameter_list too, so an unused
; receiver name is tagged like any parameter.
(parameter_list [
  (parameter_declaration name: (identifier) @parameter_name)
  (variadic_parameter_declaration name: (identifier) @parameter_name)
])

(block) @body

(comment) @comment

(identifier) @name

; Name a unit by its defining name, not the first identifier the lexical scan
; reaches: a method's receiver variable precedes its name.
(function_declaration name: (identifier) @def_name)
(method_declaration name: (field_identifier) @def_name)

(return_statement) @return

(call_expression) @call

(binary_expression) @binary_expr

[(if_statement) (expression_switch_statement) (type_switch_statement)] @conditional

; NPath construct families. Go has no ternary or try construct. The default case has
; its own node type, so it joins @case explicitly.
(for_statement) @loop
[(expression_switch_statement) (type_switch_statement) (select_statement)] @switch
[(expression_case) (type_case) (communication_case) (default_case)] @case

[(return_statement) (break_statement) (continue_statement)] @terminal
