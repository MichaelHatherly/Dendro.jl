; C lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; and struct names hoist to the enclosing scope so a sibling reference resolves.
; Parameters are not captured: they form no cross-function cohesion edge. A struct
; or enum specifier is a definition and a scope only with a body: `struct client;`
; and the `struct client *c` in a prototype name the type, they do not define it.

; --- Scope regions ---
(translation_unit) @scope
(function_definition) @scope
(struct_specifier body: (field_declaration_list)) @scope
(enum_specifier body: (enumerator_list)) @scope

; --- Function names (hoisted) ---
(function_definition declarator: (function_declarator declarator: (identifier) @definition.function))

; --- Type names (hoisted) ---
(struct_specifier name: (type_identifier) @definition.struct body: (field_declaration_list))

; --- Local bindings ---
(init_declarator declarator: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier)] @reference
