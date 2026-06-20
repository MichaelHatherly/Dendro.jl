; TypeScript linkage. `import { x, y } from './mod'` brings named exports into scope;
; @import marks the statement, @import.from the module specifier, @import.name each
; imported name. Only an exported declaration is visible to an importer, marked @export.
; A class name is a `type_identifier` here, unlike JavaScript. Node types match
; tree-sitter-typescript.

; --- named imports ---
(import_statement) @import
(import_statement source: (string) @import.from)
(import_statement (import_clause (named_imports (import_specifier name: (identifier) @import.name))))

; --- exports ---
(export_statement declaration: (function_declaration name: (identifier) @export))
(export_statement declaration: (class_declaration name: (type_identifier) @export))
(export_statement declaration: (lexical_declaration (variable_declarator name: (identifier) @export)))
(export_statement (export_clause (export_specifier name: (identifier) @export)))
