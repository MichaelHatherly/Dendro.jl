; PHP linkage. `use App\Foo` names `Foo` in file `App/Foo.php`, the PSR-4 convention;
; @import marks the declaration, @import.from the qualified name, @import.name the final
; segment. Node types match tree-sitter-php.

(namespace_use_declaration) @import
(namespace_use_clause (qualified_name) @import.from)
(namespace_use_clause (qualified_name (name) @import.name))
