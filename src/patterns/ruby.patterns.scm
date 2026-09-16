; The shipped pack, realised for Ruby. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for Ruby, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Five of the pack's rules have no Ruby pattern. `nothing_equality` would name `== nil`,
; where `nil?` is the idiom and `==` on nil is not the trap it is elsewhere. `type_equality`
; has no spelling short of comparing `class` objects, `redundant_collect` no lazy sequence a
; call would have iterated, `redundant_default` no `fetch` carrying the default it already
; has, and `each` rather than an index loop is how Ruby walks a collection.
;
; A guard is written as a modifier on the statement it guards, so the rules reading one
; match an `if_modifier` or `unless_modifier` rather than a block.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^#[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch yields a boolean literal, so the test is being written out a second time. `c`
; is the whole of it. Both spellings, since a Ruby branch is as often its value as a
; `return`.
((if
   consequence: (then . [(true) (false)] .)
   alternative: (else . [(true) (false)] .))
 @boolean_return)
((if
   consequence: (then . (return (argument_list . [(true) (false)] .)) .)
   alternative: (else . (return (argument_list . [(true) (false)] .)) .))
 @boolean_return)

; An `elsif` testing what the branch above it already tested. The earlier branch takes every
; value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
;
; The chain nests rather than flattening, so this reads one link at a time: a condition
; repeated two links down is not reported.
((if condition: (_) @_c alternative: (elsif condition: (_) @_e))
 @unreachable_branch (#structure-eq? @_c @_e))
((elsif condition: (_) @_a alternative: (elsif condition: (_) @_b))
 @unreachable_branch (#structure-eq? @_a @_b))

; Comparing two values and then yielding the one the comparison picked. `max` and `min` say
; it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if a == b` picks nothing.
((if
   condition: (binary left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b)
   consequence: (then . (_) @_x .)
   alternative: (else . (_) @_y .))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))
((if
   condition: (binary left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b)
   consequence: (then . (return (argument_list . (_) @_x .)) .)
   alternative: (else . (return (argument_list . (_) @_y .)) .))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `rescue` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
;
; The rescued class has to be one of the broad ones. `rescue JSON::ParserError` converts a
; named failure into a value on purpose, the same call Python's `except ValueError` gets, and
; a bare `rescue` is `broad_catch`'s to report.
((rescue
   exceptions: (exceptions (constant) @_t)
   body: (then . (return) @_r .))
 @swallowed_error
 (#any-of? @_t "StandardError" "Exception")
 (#match? @_r "^return([ \t]+(nil|false|true|0|\\[\\]|\\{\\}))?$"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if flag` is how it is asked.
((binary operator: ["==" "!=" "==="] right: [(true) (false)]) @boolean_equality)
((binary left: [(true) (false)] operator: ["==" "!=" "==="]) @boolean_equality)

; `xs.size == 0` counts every element to find out whether there are any. `xs.empty?` asks the
; question directly. Both operand orders, since the comparison reads naturally either way.
((binary
   left: (call method: (identifier) @_m)
   operator: ["==" "!="]
   right: (integer) @_z)
 @empty_check (#any-of? @_m "size" "length" "count") (#eq? @_z "0"))
((binary
   left: (integer) @_z
   operator: ["==" "!="]
   right: (call method: (identifier) @_m))
 @empty_check (#any-of? @_m "size" "length" "count") (#eq? @_z "0"))

; A value converted and immediately converted back. `x.to_s.to_i` writes a number out as text
; so the parser can read the number back.
((call receiver: (call method: (identifier) @_i) method: (identifier) @_o)
 @redundant_conversion (#eq? @_i "to_s") (#any-of? @_o "to_i" "to_f"))
((call receiver: (call method: (identifier) @_i) method: (identifier) @_o)
 @redundant_conversion (#any-of? @_i "to_i" "to_f") (#eq? @_o "to_s"))

; `d.keys.include?(k)` builds an array of every key and scans it to ask a question the hash
; answers itself. `d.key?(k)` is the same test without the array.
((call receiver: (call method: (identifier) @_k) method: (identifier) @_i)
 @redundant_keys (#eq? @_k "keys") (#any-of? @_i "include?" "member?"))

; An exception class with no fields and no behaviour. The name is the whole of it, and a name
; is what the `raise` site already carries. An empty class body is no node at all in this
; grammar, so emptiness is read off the declaration as written.
((class name: (constant) superclass: (superclass (constant) @_base))
 @empty_error_type
 (#match? @_base "(Error|Exception)$")
 (#match? @empty_error_type "^class[ \t]+[A-Z][A-Za-z0-9_:]*[ \t]*<[ \t]*[A-Za-z0-9_:]+[ \t]*;?[ \t\r\n]*end$"))

; A runtime type check that raises. One says the method is strict about what it takes;
; several say the signature is doing its checking in the body, where no caller can see it.
((unless_modifier
   body: (call method: (identifier) @_r)
   condition: (call method: (identifier) @_c))
 @type_check_density
 (#eq? @_r "raise") (#any-of? @_c "is_a?" "kind_of?" "instance_of?"))

; A nil guard that returns nil. One is a boundary; several mean the nil travels, and every
; caller downstream inherits the same guard.
((if_modifier
   body: (return) @_r
   condition: (call method: (identifier) @_c))
 @null_guard_density (#eq? @_c "nil?") (#match? @_r "^return([ \t]+nil)?$"))
((if
   condition: (call method: (identifier) @_c)
   consequence: (then . (return) @_r .))
 @null_guard_density (#eq? @_c "nil?") (#match? @_r "^return([ \t]+nil)?$"))

; A `begin` block carrying a `rescue`. One is error handling; several in one definition means
; the definition is several pieces of work that each fail differently.
;
; A method-level `rescue` is not counted. There is one per definition by construction, so it
; can never reach a density worth reporting.
((begin (rescue)) @try_density)
