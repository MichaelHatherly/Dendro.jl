; Bash lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; names hoist to the enclosing scope so a sibling reference resolves.

; --- Scope regions ---
(program) @scope
(function_definition) @scope

; --- Function names (hoisted) ---
(function_definition name: (word) @definition.function)

; --- Local bindings ---
(variable_assignment name: (variable_name) @definition.local)

; --- References ---
(word) @reference
