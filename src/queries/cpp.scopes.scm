; C++ lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; struct, and class names hoist to the enclosing scope so a sibling reference
; resolves; a class body is a scope so its methods hoist into it. Parameters are not
; captured: they form no cross-function cohesion edge. A struct, class, or enum
; specifier is a definition and a scope only with a body: `class Foo;` and the
; `struct Bar *q` in a prototype name the type, they do not define it.

; --- Scope regions ---
(translation_unit) @scope
(function_definition) @scope
(struct_specifier body: (field_declaration_list)) @scope
(enum_specifier body: (enumerator_list)) @scope
(class_specifier body: (field_declaration_list)) @scope
(namespace_definition) @scope

; --- Function and method names (hoisted) ---
(function_definition declarator: (function_declarator declarator: (identifier) @definition.function))
(function_definition declarator: (function_declarator declarator: (field_identifier) @definition.function))

; --- Type names (hoisted) ---
(struct_specifier name: (type_identifier) @definition.struct body: (field_declaration_list))
(class_specifier name: (type_identifier) @definition.class body: (field_declaration_list))

; --- Local bindings ---
(init_declarator declarator: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier) (field_identifier)] @reference
