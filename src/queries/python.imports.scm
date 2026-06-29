; Python linkage. `from <module> import <names>` brings specific names into the
; importing file's scope; @import marks the statement, @import.from its source module,
; @import.name each imported name. A class body is not tagged a namespace region: a
; method is reachable only as `C.method`, never importable by bare name, so it is left
; out of the corpus symbol table. Node types match tree-sitter-python.

; --- from <module> import <names> ---
(import_from_statement) @import
(import_from_statement module_name: (dotted_name) @import.from)
(import_from_statement module_name: (relative_import) @import.from)
(import_from_statement name: (dotted_name) @import.name)
