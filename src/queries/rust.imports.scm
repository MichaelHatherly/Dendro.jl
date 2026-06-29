; Rust linkage. `use a::b::c` brings item `c` from module `a::b`; `use a::b::{c, d}`
; brings several; `use a::b::*` brings every name. @import marks the statement,
; @import.from the module path, @import.name each item, absent for a wildcard so an
; empty name set stands for the whole module. The module path resolves to a file. Node
; types match tree-sitter-rust.

; --- use a::b::item ---
(use_declaration argument: (scoped_identifier path: (_) @import.from name: (identifier) @import.name)) @import

; --- use a::b::{x, y} ---
(use_declaration argument: (scoped_use_list path: (_) @import.from list: (use_list (identifier) @import.name))) @import

; --- use a::b::* ---
(use_declaration argument: (use_wildcard (_) @import.from)) @import
