; Ruby node identification. begin/rescue keeps the handler body inline rather than
; in a block node, so swallowed-rescue detection does not fit the block model and
; @catch has no pattern. The default `when` branch is excluded from @decision.
; Ruby branch bodies are `then`/inline statements, not block nodes, so the NPath
; construct families (@loop/@switch/@ternary/@try/@case) are not wired; npath on Ruby
; reduces to a sequence count.

[(method) (singleton_method)] @function

[(if) (elsif) (unless) (while) (until) (for) (when) (rescue)
 (conditional)] @decision

(elsif) @continuation

[(if) (unless) (while) (until) (for) (case) (begin)] @nesting

["&&" "||" "and" "or"] @short_circuit

(method_parameters) @parameter

(body_statement) @body

(comment) @comment

(identifier) @name

(return) @return

(ensure) @finally

(call) @call

(binary) @binary_expr

[(if) (unless) (case)] @conditional

[(return) (break) (next)] @terminal
