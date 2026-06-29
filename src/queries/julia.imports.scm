; Julia linkage. A third per-language query feeding the corpus binding graph:
; @module marks a namespace region and @module.name its name, so a nested `module`
; is told apart from an ordinary scope (both are @scope in the scopes query).
; @include.path is the literal path of an `include(...)` call, the splice edge that
; joins two files into one module. Node types match tree-sitter-julia.

; --- Namespace regions ---
(module_definition name: (identifier) @module.name) @module

; --- include("path") splice ---
(call_expression
  (identifier) @_inc
  (argument_list (string_literal) @include.path)
  (#eq? @_inc "include"))
