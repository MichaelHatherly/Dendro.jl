; PHP lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; method, and class names hoist to the enclosing scope so a sibling reference
; resolves; a class body is a scope so its methods hoist into it. Parameters are not
; captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(program) @scope
(function_definition) @scope
(method_declaration) @scope
(class_declaration) @scope

; --- Function and method names (hoisted) ---
(function_definition name: (name) @definition.function)
(method_declaration name: (name) @definition.function)

; --- Class names (hoisted) ---
(class_declaration name: (name) @definition.class)

; --- Const bindings ---
(const_element (name) @definition.const)

; --- References ---
(name) @reference
