; C lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; and struct names hoist to the enclosing scope so a sibling reference resolves.
; Parameters are not captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(translation_unit) @scope
(function_definition) @scope
(struct_specifier) @scope
(enum_specifier) @scope

; --- Function names (hoisted) ---
(function_definition declarator: (function_declarator declarator: (identifier) @definition.function))

; --- Type names (hoisted) ---
(struct_specifier name: (type_identifier) @definition.struct)

; --- Local bindings ---
(init_declarator declarator: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier)] @reference
