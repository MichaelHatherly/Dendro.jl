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

; --- Registered definitions ---
; A decorator hands its definition to the code that applies it, a route table, a test
; runner, a plugin registry, which calls it by registration. The decorators that only
; wrap or annotate ordinary code are excluded by their final name.
(decorated_definition
  (decorator
    [(identifier) @_wrap
     (attribute attribute: (identifier) @_wrap)
     (call function: [(identifier) @_wrap (attribute attribute: (identifier) @_wrap)])])
  definition: [
    (function_definition name: (identifier) @external_root)
    (class_definition name: (identifier) @external_root)]
  (#not-any-of? @_wrap
    "abstractmethod" "asynccontextmanager" "cache" "cached_property" "classmethod"
    "contextmanager" "dataclass" "final" "lru_cache" "overload" "override" "property"
    "runtime_checkable" "staticmethod" "total_ordering" "wraps"))
