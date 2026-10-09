; The shipped pack, realised for C. `builtin.toml` says what each rule means; this file says
; what it looks like. A rule with no pattern here never fires for C, which is ordinary: the
; declaration is language-independent and no grammar spells every shape.
;
; C realises six of the eighteen, the fewest of any language with a query, and the twelve
; gaps are the language rather than the queries. There is no `try` to count and no `catch`
; to swallow an error in, so `try_density`, `swallowed_error` and `type_check_density` name
; nothing. There is no container protocol behind a length, no key view, no dictionary
; `get`, no exception type, and no runtime type to compare, so `empty_check`,
; `redundant_keys`, `redundant_default`, `empty_error_type` and `type_equality` name nothing
; either. `redundant_conversion` would need a conversion library the language does not
; standardise on, and an index loop over an array is how C walks one.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   consequence: (compound_statement . (return_statement [(true) (false)]) .)
   alternative: (else_clause (compound_statement . (return_statement [(true) (false)]) .)))
 @boolean_return)

; An `else if` testing what the branch above it already tested. The earlier branch takes
; every value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
;
; The chain nests rather than flattening, so this reads one link at a time: a condition
; repeated two links down is not reported.
((if_statement
   condition: (_) @_c
   alternative: (else_clause (if_statement condition: (_) @_e)))
 @unreachable_branch (#structure-eq? @_c @_e))

; Comparing two values and then returning the one the comparison picked. A `max` macro says
; it in one call and says which of the two was meant. The operator is restricted to the
; orderings: `if (a == b)` picks nothing.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b))
   consequence: (compound_statement . (return_statement (_) @_x) .)
   alternative: (else_clause (compound_statement . (return_statement (_) @_y) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if (flag)` is how it is asked.
((binary_expression operator: ["==" "!="] right: [(true) (false)]) @boolean_equality)
((binary_expression left: [(true) (false)] operator: ["==" "!="]) @boolean_equality)

; A null guard that returns null. One is a boundary; several mean the null travels, and
; every caller downstream inherits the same guard. Both the explicit comparison and the
; truthiness test C reads a pointer with, and both body shapes, since a one-line guard
; carries its `return` without a block.
((if_statement
   condition: (parenthesized_expression (binary_expression left: (_) operator: "==" right: (null)))
   consequence: (compound_statement . (return_statement (null)) .))
 @null_guard_density)
((if_statement
   condition: (parenthesized_expression (binary_expression left: (_) operator: "==" right: (null)))
   consequence: (return_statement (null)))
 @null_guard_density)
((if_statement
   condition: (parenthesized_expression (unary_expression operator: "!"))
   consequence: (compound_statement . (return_statement (null)) .))
 @null_guard_density)
((if_statement
   condition: (parenthesized_expression (unary_expression operator: "!"))
   consequence: (return_statement (null)))
 @null_guard_density)
