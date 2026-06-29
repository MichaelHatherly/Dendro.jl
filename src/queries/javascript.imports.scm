; JavaScript linkage. `import { x, y } from './mod'` brings named exports into scope;
; @import marks the statement, @import.from the module specifier, @import.name each
; imported name. Only an exported declaration is visible to an importer, marked @export.
; Node types match tree-sitter-javascript.

; --- named imports ---
; Only a named-import clause brings exports into bare scope. A default, namespace, or
; side-effect import binds the module itself, not its named exports, so it marks no
; region: an empty name set is reserved for a genuine wildcard, which JavaScript lacks.
(import_statement
  (import_clause (named_imports))
  source: (string) @import.from) @import
(import_statement (import_clause (named_imports (import_specifier name: (identifier) @import.name))))

; --- exports ---
(export_statement declaration: (function_declaration name: (identifier) @export))
(export_statement declaration: (class_declaration name: (identifier) @export))
(export_statement declaration: (lexical_declaration (variable_declarator name: (identifier) @export)))
(export_statement (export_clause (export_specifier name: (identifier) @export)))
