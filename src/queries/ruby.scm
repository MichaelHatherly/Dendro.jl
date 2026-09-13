; Ruby node identification. begin/rescue keeps the handler body inline rather than
; in a block node, so swallowed-rescue detection does not fit the block model and
; @catch has no pattern. The default `when` branch is excluded from @decision.

; `rescue Exception` swallows interrupts and exits; a bare `rescue` catches
; StandardError, the idiomatic default, and is not tagged. The rescue is what is tagged,
; so `broad_catches` can read its body; `@_exc` anchors the text test and names no concept.
((rescue exceptions: (exceptions (constant) @_exc)) @broad_catch
  (#eq? @_exc "Exception"))

; `raise` is a call, or a bare identifier when it takes no argument; either way a
; handler ending in one passes its error on.
((identifier) @raise (#eq? @raise "raise"))
((call method: (identifier) @_raise) @raise (#eq? @_raise "raise"))
; Ruby branch bodies are `then`/inline statements, not block nodes, so the NPath
; construct families (@loop/@switch/@ternary/@try/@case) are not wired; npath on Ruby
; reduces to a sequence count.

; A `def … end` delimits its body with the construct, so an empty one is an empty body,
; not a declaration; @requires_body marks that for `empty_body`.
[(method) (singleton_method)] @function @requires_body

[(if) (elsif) (unless) (while) (until) (for) (when) (rescue)
 (conditional)] @decision

; The decision count's reading of a case: the arms @decision charges one apiece, and the
; case that replaces them. Ruby wires no npath switch family, so these two are the only
; place the grammar's case nodes are named; `else` is no decision, so it is no arm either.
; A `case ... in` pattern match is a case_match, which @decision never counts, so it is
; left alone here too.
(when) @switch_arm
(case) @switch_stmt

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

; RDoc takes whatever `#` lines precede a definition, so every comment is documentation,
; the same reading Go gets for the same reason.
(comment) @doc

; RDoc's `:nodoc:` declares the definition on its line out of the documented surface, and
; `:nodoc: all` on a class line covers the members too.
((comment) @nodoc (#match? @nodoc ":nodoc:"))

(identifier) @name

(return) @return

(ensure) @finally

(call) @call

; A call's target name. A bare identifier is ambiguous between a variable read and
; a zero-argument call, so only explicit call nodes count.
(call method: (identifier) @callee)

(binary) @binary_expr

[(if) (unless) (case)] @conditional

[(return) (break) (next)] @terminal

; --- Class-level cohesion -------------------------------------------------
; The container owning methods and the state they share. A module holds no instance
; state, so it is not one.
(class) @class

; The declared name, so a finding about the class names the class. Ruby's `@name` tags
; identifiers and a class name is a constant, so without this the class goes unnamed.
(class name: (constant) @def_name)

; A field use: an instance variable is the whole of Ruby's instance state.
(instance_variable) @field

; `initialize` assigns every field a class has, so leaving it among the methods would read
; every class as one concern. `@_ctor` anchors the text test and names no concept.
((method name: (identifier) @_ctor) @constructor (#eq? @_ctor "initialize"))
