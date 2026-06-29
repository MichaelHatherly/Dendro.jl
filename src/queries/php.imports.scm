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
