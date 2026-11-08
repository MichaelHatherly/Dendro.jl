; PHP linkage. `use App\Foo` names `Foo` in file `App/Foo.php`, the PSR-4 convention;
; @import marks the declaration, @import.from the qualified name, @import.name the final
; segment. @module marks a class body a namespace so its methods are top-level symbols,
; the granularity a private method's dead-code check needs. Node types match
; tree-sitter-php.

; --- Class namespace ---
(class_declaration name: (name) @module.name) @module

(namespace_use_declaration) @import
(namespace_use_clause (qualified_name) @import.from)
(namespace_use_clause (qualified_name (name) @import.name))

; --- Registered definitions ---
; An attribute hands its method, function, or class to a framework that calls it by
; registration, a route, a listener, a command. The engine's own attributes only
; annotate ordinary code and are excluded.
(method_declaration
  attributes: (attribute_list (attribute_group (attribute [(name) @_wrap (qualified_name (name) @_wrap)])))
  name: (name) @external_root
  (#not-any-of? @_wrap "Override" "Deprecated" "ReturnTypeWillChange" "SensitiveParameter" "NoDiscard"))
(function_definition
  attributes: (attribute_list (attribute_group (attribute [(name) @_wrap (qualified_name (name) @_wrap)])))
  name: (name) @external_root
  (#not-any-of? @_wrap "Deprecated" "ReturnTypeWillChange" "SensitiveParameter" "NoDiscard"))
(class_declaration
  attributes: (attribute_list (attribute_group (attribute [(name) @_wrap (qualified_name (name) @_wrap)])))
  name: (name) @external_root
  (#not-any-of? @_wrap "AllowDynamicProperties" "Attribute" "Deprecated"))
