; TypeScript node identification. The default switch branch has its own node type
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

; The decision count's reading of a switch: the arms @decision charges one apiece, and the
; switch that replaces them. switch_default is no decision, so it is no arm either.
(switch_case) @switch_arm
(switch_statement) @switch_stmt

[(if_statement) (for_statement) (for_in_statement) (while_statement)
 (do_statement) (switch_statement) (try_statement)] @nesting

["&&" "||"] @short_circuit

(formal_parameters) @parameter

; A parameter's name identifier: required, optional, and rest forms, plus the bare
; single-parameter arrow that carries no parameter list. A destructuring pattern
; introduces no single name and is not tagged.
(formal_parameters [
  (required_parameter pattern: (identifier) @parameter_name)
  (optional_parameter pattern: (identifier) @parameter_name)
  (required_parameter pattern: (rest_pattern (identifier) @parameter_name))
])
(arrow_function parameter: (identifier) @parameter_name)

(statement_block) @body

(catch_clause) @catch

(comment) @comment

; TSDoc opens with `/**`. An ordinary comment is an aside, not documentation.
((comment) @doc (#match? @doc "^/\\*\\*"))

; An `override` method inherits the overridden method's documentation.
(method_definition (override_modifier)) @inherits_doc

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

; A call's target name: the called identifier, or a member call's property name.
(call_expression function: (identifier) @callee)
(call_expression function: (member_expression property: (property_identifier) @callee))

(binary_expression) @binary_expr

[(if_statement) (switch_statement)] @conditional

; NPath construct families.
[(for_statement) (for_in_statement) (while_statement) (do_statement)] @loop
(switch_statement) @switch
[(switch_case) (switch_default)] @case
(ternary_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (throw_statement)] @terminal

; --- Class-level cohesion -------------------------------------------------
; The container owning methods and the state they share, in declaration, abstract and
; expression form.
[(class_declaration) (abstract_class_declaration) (class)] @class

; The class's declared name, so a finding about the class names the class rather than the
; first method the lexical scan reaches. TypeScript names a class with a type identifier.
; An anonymous class expression takes the name it is bound to.
(class_declaration name: (type_identifier) @def_name)
(abstract_class_declaration name: (type_identifier) @def_name)
(class name: (type_identifier) @def_name)
(variable_declarator name: (identifier) @def_name value: (class))

; A field use through the instance.
(member_expression object: (this) property: (property_identifier) @field)

; A constructor assigns every field a class has, so leaving it among the methods would
; read every class as one concern. `@_ctor` anchors a text test and names no concept.
((method_definition name: (property_identifier) @_ctor) @constructor
  (#eq? @_ctor "constructor"))
