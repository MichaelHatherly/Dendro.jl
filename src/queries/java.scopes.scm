; Java lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Method
; and class names hoist to the enclosing scope so a sibling reference resolves; a
; class body is a scope so its methods hoist into it. A type use is a `type_identifier`,
; so it is captured too: a same-package class reference resolves against the package.
; Parameters are not captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(program) @scope
(class_declaration) @scope
(interface_declaration) @scope
(method_declaration) @scope
(constructor_declaration) @scope

; --- Method names (hoisted) ---
(method_declaration name: (identifier) @definition.function)

; --- Class names (hoisted) ---
(class_declaration name: (identifier) @definition.class)

; --- Local bindings ---
(local_variable_declaration declarator: (variable_declarator name: (identifier) @definition.local))

; --- References ---
[(identifier) (type_identifier)] @reference
