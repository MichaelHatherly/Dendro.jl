; Python lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; and class names hoist to the enclosing scope so a sibling reference resolves.
; Parameters are not captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(module) @scope
(function_definition) @scope
(class_definition) @scope
(lambda) @scope

; --- Function names (hoisted) ---
(function_definition name: (identifier) @definition.function)

; --- Class names (hoisted) ---
(class_definition name: (identifier) @definition.class)

; --- Local bindings ---
(assignment left: (identifier) @definition.local)

; --- References ---
(identifier) @reference
