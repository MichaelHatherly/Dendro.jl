; Ruby node identification. begin/rescue keeps the handler body inline rather than
; in a block node, so swallowed-rescue detection does not fit the block model and
; @catch has no pattern. The default `when` branch is excluded from @decision.

; `rescue Exception` swallows interrupts and exits; a bare `rescue` catches
; StandardError, the idiomatic default, and is not tagged.
(rescue exceptions: (exceptions (constant) @broad_catch)
  (#eq? @broad_catch "Exception"))
; Ruby branch bodies are `then`/inline statements, not block nodes, so the NPath
; construct families (@loop/@switch/@ternary/@try/@case) are not wired; npath on Ruby
; reduces to a sequence count.

; A `def … end` delimits its body with the construct, so an empty one is an empty body,
; not a declaration; @requires_body marks that for `empty_body`.
[(method) (singleton_method)] @function @requires_body

[(if) (elsif) (unless) (while) (until) (for) (when) (rescue)
 (conditional)] @decision

(elsif) @continuation

[(if) (unless) (while) (until) (for) (case) (begin)] @nesting

["&&" "||" "and" "or"] @short_circuit

(method_parameters) @parameter

; A parameter's name identifier: plain, optional, splat, keyword, hash-splat, and
; block forms. Block-argument parameters (`do |x|`) are not tagged; a block is not
; a unit.
(method_parameters [
  (identifier) @parameter_name
  (optional_parameter name: (identifier) @parameter_name)
  (splat_parameter name: (identifier) @parameter_name)
  (keyword_parameter name: (identifier) @parameter_name)
  (hash_splat_parameter name: (identifier) @parameter_name)
  (block_parameter name: (identifier) @parameter_name)
])

(body_statement) @body

(comment) @comment

(identifier) @name

(return) @return

(ensure) @finally

(call) @call

(binary) @binary_expr

[(if) (unless) (case)] @conditional

[(return) (break) (next)] @terminal
