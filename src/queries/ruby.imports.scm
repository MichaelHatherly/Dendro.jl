; Ruby linkage. `require_relative 'foo'` loads a file's top-level definitions into the
; global namespace, a splice; @include.path is the required path, extension dropped. A
; module or class body is a namespace, so a method inside it is not loaded as a global
; name. Node types match tree-sitter-ruby.

(call
  method: (identifier) @_m
  arguments: (argument_list (string (string_content) @include.path))
  (#eq? @_m "require_relative"))

(module name: (constant) @module.name) @module
(class name: (constant) @module.name) @module
