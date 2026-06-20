; Rust linkage. `use a::b::c` brings item `c` from module `a::b` into scope; @import
; marks the statement, @import.from the full path, @import.name the final item. The
; module path resolves to a file, the item is the visible name. Node types match
; tree-sitter-rust.

(use_declaration) @import
(use_declaration argument: (scoped_identifier) @import.from)
(use_declaration argument: (scoped_identifier name: (identifier) @import.name))
