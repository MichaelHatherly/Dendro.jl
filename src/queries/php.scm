; PHP node identification. The default switch branch has its own node type and is
; excluded from @decision.

[(function_definition) (method_declaration)] @function

[(if_statement) (else_if_clause) (for_statement) (foreach_statement)
 (while_statement) (do_statement) (case_statement) (conditional_expression)
 (catch_clause)] @decision

(else_if_clause) @continuation

[(if_statement) (for_statement) (foreach_statement) (while_statement)
 (do_statement) (switch_statement) (try_statement)] @nesting

["&&" "||" "and" "or"] @short_circuit

(formal_parameters) @parameter

; A parameter's name, plain and variadic forms. A promoted parameter initializes a
; property by existing, so its name is never unused and is not tagged.
(formal_parameters [
  (simple_parameter name: (variable_name (name) @parameter_name))
  (variadic_parameter name: (variable_name (name) @parameter_name))
])

; A promoted constructor parameter does the constructor's work in the signature, so an
; empty body is not an empty implementation.
(property_promotion_parameter) @init

(compound_statement) @body

(catch_clause) @catch

; `catch (Throwable)` swallows errors as well as exceptions, plain or
; namespace-qualified. `catch (Exception)` is merely wide and not tagged.
(catch_clause type: (type_list (named_type (name) @broad_catch))
  (#eq? @broad_catch "Throwable"))
(catch_clause type: (type_list (named_type (qualified_name (name) @broad_catch)))
  (#eq? @broad_catch "Throwable"))

(comment) @comment

(name) @name

(return_statement) @return

(finally_clause) @finally

(function_call_expression) @call

; A call's target name: the called name, a namespaced call's final name, or a
; member call's method name.
(function_call_expression function: (name) @callee)
(function_call_expression function: (qualified_name (name) @callee))
(member_call_expression name: (name) @callee)

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families.
[(for_statement) (foreach_statement) (while_statement) (do_statement)] @loop
(switch_statement) @switch
[(case_statement) (default_statement)] @case
(conditional_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement)] @terminal

; `throw` is an expression wrapped in a statement; tag the statement so code after
; it in the same block reads as unreachable.
(expression_statement (throw_expression)) @terminal

; --- Class-level cohesion -------------------------------------------------
; The containers owning methods and the state they share. A trait is one: it declares
; properties and the methods that use them. So is an enum, whose cases are instance state.
[(class_declaration) (trait_declaration) (enum_declaration)] @class

; The declared name, so a finding about the class names the class.
(class_declaration name: (name) @def_name)
(trait_declaration name: (name) @def_name)
(enum_declaration name: (name) @def_name)

; A field use through the instance. `@_this` anchors the text test and names no concept.
(member_access_expression object: (variable_name (name) @_this) name: (name) @field
  (#eq? @_this "this"))

; A constructor assigns every field a class has, so leaving it among the methods would
; read every class as one concern.
((method_declaration name: (name) @_ctor) @constructor (#eq? @_ctor "__construct"))
