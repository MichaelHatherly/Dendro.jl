; Rust lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; and named-type names hoist to the enclosing scope so a sibling reference resolves;
; an impl body is a scope so its methods hoist into it. Parameters are not captured:
; they form no cross-function cohesion edge.

; --- Scope regions ---
(source_file) @scope
(function_item) @scope
(impl_item) @scope
(mod_item) @scope
(trait_item) @scope

; --- Function names (hoisted) ---
(function_item name: (identifier) @definition.function)

; --- Type names (hoisted) ---
(struct_item name: (type_identifier) @definition.struct)
(enum_item name: (type_identifier) @definition.struct)
(type_item name: (type_identifier) @definition.struct)

; --- Local bindings ---
(const_item name: (identifier) @definition.const)
(let_declaration pattern: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier)] @reference
