; C node identification. C has no finally construct, so that concept has no pattern.
;
; No @class. A struct declares fields and nothing else; the functions acting on it are
; file-scope siblings with no container node to read.

(function_definition) @function

[(if_statement) (for_statement) (while_statement) (do_statement)
 (case_statement) (conditional_expression)] @decision

; The decision count's reading of a switch: the arms @decision charges one apiece, and
; the switch that replaces them. `default:` is a case_statement, so it cancels either way.
(case_statement) @switch_arm
(switch_statement) @switch_stmt

[(if_statement) (for_statement) (while_statement) (do_statement)
 (switch_statement)] @nesting

["&&" "||"] @short_circuit

(parameter_list) @parameter

; A parameter's name identifier, through one or two pointer levels. A function-pointer
; parameter's inner name is left untagged; its shape carries no simple name.
(parameter_list (parameter_declaration declarator: [
  (identifier) @parameter_name
  (pointer_declarator declarator: (identifier) @parameter_name)
  (pointer_declarator declarator: (pointer_declarator declarator: (identifier) @parameter_name))
]))

(compound_statement) @body

(comment) @comment

; C has no docstring and most C is not Doxygen: curl and redis document with a plain
; `/* */` block above the definition, so every comment is documentation, the same reading
; Go gets for the same reason.
(comment) @doc

(identifier) @name

; Name a unit by the identifier in its declarator, not the first identifier the
; lexical scan reaches: a return-type token or storage-class macro precedes it. The
; pattern matches the function_declarator at any depth, so pointer- and
; parenthesized-return wrappers around it do not hide the name.
(function_declarator declarator: (identifier) @def_name)

; A prototype: the declaration of a function defined elsewhere, through up to two
; pointer levels of return type. curl documents at the prototype in the header, and a
; header holding one is what makes the definition API.
(declaration declarator: [
  (function_declarator)
  (pointer_declarator declarator: (function_declarator))
  (pointer_declarator declarator: (pointer_declarator declarator: (function_declarator)))
]) @prototype

(return_statement) @return

(call_expression) @call

; A call's target name: the called identifier, or a member call's field name.
(call_expression function: (identifier) @callee)
(call_expression function: (field_expression field: (field_identifier) @callee))

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families. C has no try construct.
[(for_statement) (while_statement) (do_statement)] @loop
(switch_statement) @switch
(case_statement) @case
(conditional_expression) @ternary

[(return_statement) (break_statement) (continue_statement)] @terminal
