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

; A parameter's name identifier: plain, pointer, reference, and defaulted forms. A
; function-pointer parameter's inner name is left untagged; its shape carries no
; simple name.
(parameter_list [
  (parameter_declaration declarator: [
    (identifier) @parameter_name
    (pointer_declarator declarator: (identifier) @parameter_name)
    (pointer_declarator declarator: (pointer_declarator declarator: (identifier) @parameter_name))
    (reference_declarator (identifier) @parameter_name)
  ])
  (optional_parameter_declaration declarator: [
    (identifier) @parameter_name
    (pointer_declarator declarator: (identifier) @parameter_name)
    (reference_declarator (identifier) @parameter_name)
  ])
])

; A member-initializer list does the constructor's work before the body, so an empty
; body is not an empty implementation. A project macro between the return type and the
; name (`FMT_INLINE T(int x) : x_(x) {}`) defeats the parse, leaving the initializer
; list as a `bitfield_clause`; a bitfield never appears in a real function body, so
; inside a unit it is always a misparsed initializer list and marks init too.
(field_initializer_list) @init
(bitfield_clause) @init

(compound_statement) @body

(catch_clause) @catch

; `catch (...)` handles every exception with no way to inspect it.
((catch_clause parameters: (parameter_list "...")) @broad_catch)

(comment) @comment

(identifier) @name

; Name a unit by the name in its declarator, not the first identifier the lexical
; scan reaches: a return-type token, storage-class macro, or template parameter
; precedes it. The declarator may be a free or member name, a qualified
; `Class::method` (named by its final component), a destructor, or an operator.
(function_declarator declarator: (identifier) @def_name)
(function_declarator declarator: (field_identifier) @def_name)
(function_declarator declarator: (qualified_identifier name: (identifier) @def_name))
(function_declarator declarator: (destructor_name) @def_name)
(function_declarator declarator: (operator_name) @def_name)

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
