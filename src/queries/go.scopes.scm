; Go lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; method, and type names hoist to the enclosing scope so a sibling reference
; resolves. Parameters are not captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(source_file) @scope
(function_declaration) @scope
(method_declaration) @scope

; --- Function and method names (hoisted) ---
(function_declaration name: (identifier) @definition.function)
(method_declaration name: (field_identifier) @definition.function)

; --- Type names (hoisted) ---
(type_spec name: (type_identifier) @definition.struct)

; --- Local bindings ---
(const_spec name: (identifier) @definition.const)
(short_var_declaration left: (expression_list (identifier) @definition.local))

; --- References ---
[(identifier) (type_identifier) (field_identifier)] @reference
