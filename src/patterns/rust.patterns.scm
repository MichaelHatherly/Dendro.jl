; The shipped pack, realised for Rust. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for Rust, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Nine of the pack's rules have no Rust pattern. Rust returns `Result` rather than raising,
; so `try_density`, `swallowed_error` and `type_check_density` name nothing. `Option` has no
; null literal to compare against and the type system settles what `type_equality` would
; ask. The rest have no spelling here: no key view, no map lookup carrying an explicit
; default, no lazy sequence a surrounding call would have iterated, and no exception type.
;
; An `if` is an expression, so a branch is a block whose value is its last expression and
; `return` is an `return_expression` inside an `expression_statement`. Every rule reading a
; branch is written twice, once per spelling.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((line_comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t]*$"))

; Each branch yields a boolean literal, so the test is being written out a second time. `c`
; is the whole of it.
((if_expression
   consequence: (block . (boolean_literal) .)
   alternative: (else_clause (block . (boolean_literal) .)))
 @boolean_return)
((if_expression
   consequence: (block . (expression_statement (return_expression (boolean_literal))) .)
   alternative: (else_clause (block . (expression_statement (return_expression (boolean_literal))) .)))
 @boolean_return)

; An `else if` testing what the branch above it already tested. The earlier branch takes
; every value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
;
; The chain nests rather than flattening, so this reads one link at a time: a condition
; repeated two links down is not reported.
((if_expression
   condition: (_) @_c
   alternative: (else_clause (if_expression condition: (_) @_e)))
 @unreachable_branch (#structure-eq? @_c @_e))

; Comparing two values and then yielding the one the comparison picked. `max` and `min` say
; it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if a == b` picks nothing.
((if_expression
   condition: (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b)
   consequence: (block . (_) @_x .)
   alternative: (else_clause (block . (_) @_y .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))
((if_expression
   condition: (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b)
   consequence: (block . (expression_statement (return_expression (_) @_x)) .)
   alternative: (else_clause (block . (expression_statement (return_expression (_) @_y)) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if flag` is how it is asked.
((binary_expression operator: ["==" "!="] right: (boolean_literal)) @boolean_equality)
((binary_expression left: (boolean_literal) operator: ["==" "!="]) @boolean_equality)

; `v.len() == 0` counts every element to find out whether there are any. `v.is_empty()` asks
; the question directly. Both operand orders, since the comparison reads naturally either
; way.
((binary_expression
   left: (call_expression
     function: (field_expression field: (field_identifier) @_f)
     arguments: (arguments))
   operator: ["==" "!="]
   right: (integer_literal) @_z)
 @empty_check (#eq? @_f "len") (#eq? @_z "0"))
((binary_expression
   left: (integer_literal) @_z
   operator: ["==" "!="]
   right: (call_expression
     function: (field_expression field: (field_identifier) @_f)
     arguments: (arguments)))
 @empty_check (#eq? @_f "len") (#eq? @_z "0"))

; A value converted and immediately converted back. `x.to_string().parse()` writes a number
; out as text so the parser can read the number back.
((call_expression
   function: (field_expression
     value: (call_expression
       function: (field_expression field: (field_identifier) @_i)
       arguments: (arguments))
     field: (field_identifier) @_o)
   arguments: (arguments))
 @redundant_conversion (#eq? @_i "to_string") (#eq? @_o "parse"))

; `for i in 0..v.len()` loops over positions to reach elements. `for item in &v` reaches
; them, and `v.iter().enumerate()` reaches them with the position when the position is
; wanted too.
((for_expression
   value: (range_expression
     . (integer_literal) @_lo
     . (call_expression
       function: (field_expression field: (field_identifier) @_f)
       arguments: (arguments)) .))
 @length_index_range (#eq? @_lo "0") (#eq? @_f "len"))

; A `None` guard that yields `None`. One is a boundary; several mean the `None` travels, and
; every caller downstream inherits the same guard.
((if_expression
   condition: (call_expression
     function: (field_expression field: (field_identifier) @_f)
     arguments: (arguments))
   consequence: (block . (expression_statement (return_expression (identifier) @_n)) .))
 @null_guard_density (#eq? @_f "is_none") (#eq? @_n "None"))
