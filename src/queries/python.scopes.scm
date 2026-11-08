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

; --- Fields ---
; A field `__init__` assigns through `self` hoists into the class body enclosing
; `__init__`, so methods reading or writing `self.name` link. Only `__init__` declares
; one: an assignment in another method is a use of the field, not a second definition.
(function_definition
  name: (identifier) @_init
  body: (block
    (expression_statement
      (assignment left: (attribute object: (identifier) @_self attribute: (identifier) @definition.property))))
  (#eq? @_init "__init__")
  (#eq? @_self "self"))

; --- Quoted annotations ---
; A quoted annotation (`x: "Node"`) names a type the file cannot spell yet. Only a bare
; name is read; a quoted expression (`"list[Node]"`) is left unparsed.
((string_content) @reference
  (#has-ancestor? @reference type)
  (#match? @reference "^[A-Za-z_][A-Za-z0-9_]*$"))
