; C++ lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; struct, and class names hoist to the enclosing scope so a sibling reference
; resolves; a class body is a scope so its methods hoist into it. Parameters are not
; captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(translation_unit) @scope
(function_definition) @scope
(struct_specifier) @scope
(enum_specifier) @scope
(class_specifier) @scope
(namespace_definition) @scope

; --- Function and method names (hoisted) ---
(function_definition declarator: (function_declarator declarator: (identifier) @definition.function))
(function_definition declarator: (function_declarator declarator: (field_identifier) @definition.function))

; --- Type names (hoisted) ---
(struct_specifier name: (type_identifier) @definition.struct)
(class_specifier name: (type_identifier) @definition.class)

; --- Local bindings ---
(init_declarator declarator: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier) (field_identifier)] @reference
