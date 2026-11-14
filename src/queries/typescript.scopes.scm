; TypeScript lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function,
; method, class, and interface names hoist to the enclosing scope so a sibling
; reference resolves; a class body or object literal is a scope so its methods hoist
; into it, where `this.name` finds them, and never reach file scope as definitions.
; A field binds in the class body too, so methods sharing `this.field` link. Other
; parameters are not captured: they form no cross-function cohesion edge.

; --- Scope regions ---
(program) @scope
(function_declaration) @scope
(method_definition) @scope
(arrow_function) @scope
(class_body) @scope
(object) @scope
(interface_declaration) @scope

; --- Function and method names (hoisted) ---
(function_declaration name: (identifier) @definition.function)
(method_definition name: (property_identifier) @definition.function)

; --- Type names (hoisted) ---
(class_declaration name: (type_identifier) @definition.class)
(interface_declaration name: (type_identifier) @definition.struct)
(type_alias_declaration name: (type_identifier) @definition.struct)

; --- Type imports ---
; A type import names a type defined in another file. Units sharing it link within the
; file, and its uses stay cross-file references. A value import is a shared utility, not
; a shared concern, so it binds nothing.
(import_statement "type" (import_clause (identifier) @definition.import))
(import_statement "type" (import_clause (named_imports (import_specifier !alias name: (identifier) @definition.import))))
(import_statement "type" (import_clause (named_imports (import_specifier alias: (identifier) @definition.import))))
(import_specifier "type" !alias name: (identifier) @definition.import)
(import_specifier "type" alias: (identifier) @definition.import)

; --- Fields ---
; A declared field binds in the class body directly. A parameter property
; (`constructor(private x: T)`) declares a field from inside the constructor's scope,
; so its kind hoists it one level, into the class body.
(public_field_definition name: (property_identifier) @definition.field)
(required_parameter (accessibility_modifier) pattern: (identifier) @definition.property)
(required_parameter "readonly" pattern: (identifier) @definition.property)
(optional_parameter (accessibility_modifier) pattern: (identifier) @definition.property)
(optional_parameter "readonly" pattern: (identifier) @definition.property)

; --- Local bindings ---
(variable_declarator name: (identifier) @definition.local)

; --- References ---
[(identifier) (type_identifier) (property_identifier)] @reference

; A shorthand property (`{ name }`) reads the variable it names, so it is a use.
(shorthand_property_identifier) @reference
