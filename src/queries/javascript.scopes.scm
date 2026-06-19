; JavaScript lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; method, and class names hoist to the enclosing scope so a sibling reference
; resolves; a class body is a scope so its methods hoist into it. Parameters are not
; captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(program) @scope
(function_declaration) @scope
(method_definition) @scope
(arrow_function) @scope
(class_body) @scope

; --- Function and method names (hoisted) ---
(function_declaration name: (identifier) @definition.function)
(method_definition name: (property_identifier) @definition.function)

; --- Class names (hoisted) ---
(class_declaration name: (identifier) @definition.class)

; --- Local bindings ---
(variable_declarator name: (identifier) @definition.local)

; --- References ---
[(identifier) (property_identifier)] @reference
