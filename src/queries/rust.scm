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

; A parameter's name identifier. `self` and destructuring patterns introduce no
; simple name and are not tagged; closure parameters belong to no unit.
(parameters (parameter pattern: (identifier) @parameter_name))

(block) @body

[(line_comment) (block_comment)] @comment

; `///` and `/** */` document the item below them, and the grammar marks both with an
; outer doc marker. `//!` carries an inner marker and documents the module around it; a
; plain comment carries neither.
[(line_comment (outer_doc_comment_marker))
 (block_comment (outer_doc_comment_marker))] @doc

; An attribute is a sibling above the item it modifies, so a doc comment above one sits
; two or more lines above the definition it documents.
(attribute_item) @attribute

; rustdoc shows the trait's documentation on every method of a trait impl, so the whole
; `impl Trait for Type` block is the node. An inherent impl has no `trait` field.
(impl_item trait: (_)) @inherits_doc

(identifier) @name

(return_expression) @return

(call_expression) @call

; A call's target name: the called identifier, a method call's field name, or a
; path call's final name (`a::b::h` counts as `h`).
(call_expression function: (identifier) @callee)
(call_expression function: (field_expression field: (field_identifier) @callee))
(call_expression function: (scoped_identifier name: (identifier) @callee))

(binary_expression) @binary_expr

[(if_expression) (match_expression)] @conditional

; NPath construct families. Rust has no ternary (an `if` expression fills that role)
; or try construct; a match arm is its case body.
[(while_expression) (for_expression) (loop_expression)] @loop
(match_expression) @switch
(match_arm) @case

[(return_expression) (break_expression) (continue_expression)] @terminal

; --- Class-level cohesion -------------------------------------------------
; The container owning methods and the state they share. A struct declares the fields and
; an `impl` block holds the methods, so the `impl` is the class.
(impl_item) @class

; The type the block implements. `impl Trait for Type` names the trait first, which would
; label every trait impl in a file by its trait.
(impl_item type: (_) @def_name)

; A field use through the receiver. A tuple struct numbers its fields, so `self.0` names
; one as much as `self.name` does.
(field_expression value: (self) field: [(field_identifier) (integer_literal)] @field)

; Rust has no constructor form: `fn new` takes no receiver and touches no field through
; one, so it links nothing and needs no exclusion.
