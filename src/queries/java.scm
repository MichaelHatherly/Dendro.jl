; Java node identification. The default switch branch shares the switch_label node,
; so it adds one to @decision.

[(method_declaration) (constructor_declaration)] @function

[(if_statement) (for_statement) (enhanced_for_statement) (while_statement)
 (do_statement) (switch_label) (ternary_expression) (catch_clause)] @decision

[(if_statement) (for_statement) (enhanced_for_statement) (while_statement)
 (do_statement) (switch_expression) (try_statement)] @nesting

["&&" "||"] @short_circuit

(formal_parameters) @parameter

; A parameter's name identifier, plain and spread forms.
(formal_parameters [
  (formal_parameter name: (identifier) @parameter_name)
  (spread_parameter (variable_declarator name: (identifier) @parameter_name))
])

(block) @body

(catch_clause) @catch

; `catch (Throwable t)` swallows errors and interrupts, not just exceptions. A
; multi-catch tags when Throwable is among its types.
(catch_clause (catch_formal_parameter (catch_type (type_identifier) @broad_catch))
  (#eq? @broad_catch "Throwable"))

[(line_comment) (block_comment)] @comment

(identifier) @name

; Name a unit by its declared name, not the first identifier the lexical scan
; reaches: a leading annotation (`@Deprecated`) precedes it.
(method_declaration name: (identifier) @def_name)
(constructor_declaration name: (identifier) @def_name)

(return_statement) @return

(finally_clause) @finally

(method_invocation) @call

; A call's target name.
(method_invocation name: (identifier) @callee)

(binary_expression) @binary_expr

[(if_statement) (switch_expression)] @conditional

; NPath construct families. A switch case body is a statement group (colon form) or a
; rule (arrow form).
[(for_statement) (enhanced_for_statement) (while_statement) (do_statement)] @loop
(switch_expression) @switch
[(switch_block_statement_group) (switch_rule)] @case
(ternary_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (throw_statement)] @terminal
