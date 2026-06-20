; Python linkage. A class body is a namespace: its methods are reachable as
; attributes, never importable by bare name, so @module tells a class apart from the
; module scope. `from <module> import <names>` brings specific names into the importing
; file's scope; @import marks the statement, @import.from its source module, @import.name
; each imported name. Node types match tree-sitter-python.

; --- Namespace regions ---
(class_definition name: (identifier) @module.name) @module

; --- from <module> import <names> ---
(import_from_statement) @import
(import_from_statement module_name: (dotted_name) @import.from)
(import_from_statement module_name: (relative_import) @import.from)
(import_from_statement name: (dotted_name) @import.name)
