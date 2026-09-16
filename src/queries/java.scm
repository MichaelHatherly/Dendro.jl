; Java node identification. The default switch branch shares the switch_label node,
; so it adds one to @decision.

[(method_declaration) (constructor_declaration)] @function

[(if_statement) (for_statement) (enhanced_for_statement) (while_statement)
 (do_statement) (switch_label) (ternary_expression) (catch_clause)] @decision

; The decision count's reading of a switch: the arms @decision charges one apiece, and the
; switch that replaces them. A switch_label is the arm in both the colon and the arrow
; form, so `case 1: case 2:` falls to the one charge the switch carries. @case cannot serve
; here: it names the statement group, which npath sums a body over.
(switch_label) @switch_arm
(switch_expression) @switch_stmt

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

; Javadoc opens with `/**`. An ordinary block comment is an aside, not documentation.
((block_comment) @doc (#match? @doc "^/\\*\\*"))

; javadoc shows the overridden method's documentation on an `@Override` method with none
; of its own, so the method inherits its docs. `@_n` anchors the name test.
((method_declaration (modifiers (marker_annotation name: (identifier) @_n))) @inherits_doc
  (#eq? @_n "Override"))

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

; --- Class-level cohesion -------------------------------------------------
; The containers owning methods and the state they share. An enum constant and a record
; component are instance state as much as a field is, and the methods reading them live
; inside the declaration, so both are classes here. An interface declares no state and is
; not one.
[(class_declaration) (enum_declaration) (record_declaration)] @class

; The declared name, so a finding about the class names the class rather than the first
; method the lexical scan reaches.
(class_declaration name: (identifier) @def_name)
(enum_declaration name: (identifier) @def_name)
(record_declaration name: (identifier) @def_name)

; A field use through the instance. Java also lets a method name a field bare, which
; `@field_name` and the reference walk cover between them.
(field_access object: (this) field: (identifier) @field)

; A declared field's name. Java is the one covered language where a method may name a
; field without an instance qualifier, so it is the one query that tags this.
(field_declaration declarator: (variable_declarator name: (identifier) @field_name))

; A constructor assigns every field a class has, so leaving it among the methods would
; read every class as one concern.
(constructor_declaration) @constructor
