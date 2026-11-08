; Ruby lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Method
; and class names hoist to the enclosing scope so a sibling reference resolves; a
; class body is a scope so its methods hoist into it. Parameters are not captured:
; they form no cross-function cohesion edge.

; --- Scope regions ---
(program) @scope
(method) @scope
(singleton_method) @scope
(class) @scope
(module) @scope

; --- Method names (hoisted) ---
(method name: (identifier) @definition.function)

; --- Class names (hoisted) ---
(class name: (constant) @definition.class)

; --- Local bindings ---
(assignment left: (identifier) @definition.local)

; --- References ---
[(identifier) (constant)] @reference

; --- Instance variables ---
; An instance variable `initialize` assigns hoists into the class body enclosing
; `initialize`, and every `@name` is a use, so methods sharing one link.
(method
  name: (identifier) @_init
  body: (body_statement (assignment left: (instance_variable) @definition.property))
  (#eq? @_init "initialize"))
(instance_variable) @reference
