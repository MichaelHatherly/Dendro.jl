; Java linkage. `import com.foo.Bar` names class `Bar` in file `com/foo/Bar.java`;
; @import marks the declaration, @import.from the qualified name (the file path),
; @import.name the final class. @module marks a class body a namespace so its methods are
; top-level symbols, the granularity a private method's dead-code check needs. Node types
; match tree-sitter-java.

; --- Class namespace ---
(class_declaration name: (identifier) @module.name) @module

(import_declaration) @import
(import_declaration (scoped_identifier) @import.from)
(import_declaration (scoped_identifier name: (identifier) @import.name))

; --- Registered definitions ---
; An annotation hands its method or class to a framework that calls it by registration,
; a lifecycle hook, a test runner, an injector. The `java.lang` annotations only
; annotate ordinary code and are excluded.
(method_declaration
  (modifiers
    [(marker_annotation name: [(identifier) @_wrap (scoped_identifier name: (identifier) @_wrap)])
     (annotation name: [(identifier) @_wrap (scoped_identifier name: (identifier) @_wrap)])])
  name: (identifier) @external_root
  (#not-any-of? @_wrap "Override" "Deprecated" "SuppressWarnings" "SafeVarargs"))
(class_declaration
  (modifiers
    [(marker_annotation name: [(identifier) @_wrap (scoped_identifier name: (identifier) @_wrap)])
     (annotation name: [(identifier) @_wrap (scoped_identifier name: (identifier) @_wrap)])])
  name: (identifier) @external_root
  (#not-any-of? @_wrap "Deprecated" "SuppressWarnings" "FunctionalInterface"))
