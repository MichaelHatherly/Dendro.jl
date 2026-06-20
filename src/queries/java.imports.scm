; Java linkage. `import com.foo.Bar` names class `Bar` in file `com/foo/Bar.java`;
; @import marks the declaration, @import.from the qualified name (the file path),
; @import.name the final class. Node types match tree-sitter-java.

(import_declaration) @import
(import_declaration (scoped_identifier) @import.from)
(import_declaration (scoped_identifier name: (identifier) @import.name))
