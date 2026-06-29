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
