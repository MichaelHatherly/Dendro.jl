; The shipped pack, realised for Julia. `builtin.toml` says what each rule means; this file
; says what it looks like. Four of the pack's rules have no Julia pattern and never fire
; here: `redundant_default` and `empty_error_type` name shapes the language does not have,
; a fieldless `struct E <: Exception` being the dispatch mechanism rather than a smell.
;
; Julia holds an operator as a named child of `binary_expression`, and sibling patterns
; match in source order, so every rule reading one side of an operator is written twice,
; once per operand order.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((line_comment) @banner_comment (#match? @banner_comment "^#[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   (block . (return_statement (boolean_literal)) .)
   (else_clause (block . (return_statement (boolean_literal)) .)))
 @boolean_return)

; An `elseif` testing what an earlier branch already tested. The earlier branch takes every
; value that reaches the later one, so the later body is unreachable and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so `x > 0` beside `x>0` is one condition written twice and `x > 0` beside `y > 0`
; is two.
((if_statement . (_) @_c (elseif_clause . (_) @_e)) @unreachable_branch
 (#structure-eq? @_c @_e))
((if_statement (elseif_clause . (_) @_a) (elseif_clause . (_) @_b)) @unreachable_branch
 (#structure-eq? @_a @_b))

; Comparing two values and then returning the one the comparison picked. `max` and `min`
; say it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if a == b` picks nothing.
; The children of `if_statement` are not anchored to each other: a trailing comment on the
; `if` line is a named child sitting between the condition and the block, so an anchor
; there would leave the rule silent on the very line an author was explaining.
((if_statement
   (binary_expression . (_) @_a . (operator) @_op . (_) @_b .)
   (block . (return_statement (_) @_x) .)
   (else_clause (block . (return_statement (_) @_y) .)))
 @manual_min_max
 (#any-of? @_op ">" "<" ">=" "<=")
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `catch` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
((catch_clause (block . (return_statement) @_r .)) @swallowed_error
 (#any-of? @_r "return" "return nothing" "return false" "return true" "return 0"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if flag` is how it is asked.
((binary_expression . (_) . (operator) @_op . (boolean_literal) .) @boolean_equality
 (#any-of? @_op "==" "!=" "===" "!=="))
((binary_expression . (boolean_literal) . (operator) @_op . (_) .) @boolean_equality
 (#any-of? @_op "==" "!=" "===" "!=="))

; `length(x) == 0` counts every element to find out whether there are any. `isempty(x)`
; asks the question directly, and asks it of an iterator that has no length at all.
((binary_expression . (call_expression . (identifier) @_f) . (operator) . (integer_literal) @_z .)
 @empty_check (#eq? @_f "length") (#eq? @_z "0"))
((binary_expression . (integer_literal) @_z . (operator) . (call_expression . (identifier) @_f) .)
 @empty_check (#eq? @_f "length") (#eq? @_z "0"))

; A value converted and immediately converted back. `parse(Int, string(x))` hands `parse`
; a number written out as text so it can read the number back.
((call_expression . (identifier) @_o . (argument_list (call_expression . (identifier) @_i)))
 @redundant_conversion (#eq? @_o "parse") (#eq? @_i "string"))
((call_expression . (identifier) @_o . (argument_list . (call_expression . (identifier) @_i) .))
 @redundant_conversion (#eq? @_o "string") (#eq? @_i "parse"))

; `k in keys(d)` builds a key view to ask a question the dictionary answers itself.
; `haskey(d, k)` is the same test without the view.
((binary_expression . (_) . (operator) @_op . (call_expression . (identifier) @_f) .)
 @redundant_keys (#any-of? @_op "in" "∈") (#eq? @_f "keys"))

; `collect` builds a vector. Iterating one, or asking its length, is asking a lazy sequence
; a question it could have answered without the allocation.
((for_binding (call_expression . (identifier) @_f)) @redundant_collect (#eq? @_f "collect"))
((call_expression . (identifier) @_outer . (argument_list . (call_expression . (identifier) @_f)))
 @redundant_collect
 (#any-of? @_outer "length" "isempty" "first" "last" "sum" "maximum" "minimum")
 (#eq? @_f "collect"))

; `1:length(x)` writes down an assumption about where `x` starts that `x` is entitled to
; break. `eachindex(x)` reads it off the container, and is what every index into `x` in the
; loop body is going to need anyway.
((for_binding (range_expression . (integer_literal) @_lo . (call_expression . (identifier) @_f)))
 @length_index_range (#eq? @_lo "1") (#eq? @_f "length"))

; `typeof(x) == T` is true only for the exact type, so it is false for every subtype and
; for a wrapper the caller had every right to pass. `isa` and `<:` ask the question the
; code meant. The other side has to be a type written down, hence the capital: comparing
; two types that both arrived as values is a question `==` answers correctly.
((binary_expression . (call_expression . (identifier) @_f) . (operator) @_op . (identifier) @_t .)
 @type_equality
 (#eq? @_f "typeof") (#any-of? @_op "==" "!=") (#match? @_t "^[A-Z]"))
((binary_expression . (identifier) @_t . (operator) @_op . (call_expression . (identifier) @_f) .)
 @type_equality
 (#eq? @_f "typeof") (#any-of? @_op "==" "!=") (#match? @_t "^[A-Z]"))

; `== nothing` asks a value whether it compares equal to nothing, which is a question the
; value answers: `missing == nothing` is `missing`, and a custom `==` answers however it
; likes. `=== nothing` and `isnothing` ask identity, which is what the caller meant.
;
; Written without spaces, `x!==nothing` tokenises as the identifier `x!` and the operator
; `==`, so the correct spelling reads as the wrong one. The subtraction reads the left
; operand rather than the operator, since by then the `!` has been taken from it.
((binary_expression (operator) @_op (identifier) @_n) @nothing_equality
 (#any-of? @_op "==" "!=") (#eq? @_n "nothing"))
((binary_expression (identifier) @_n (operator) @_op) @nothing_equality
 (#any-of? @_op "==" "!=") (#eq? @_n "nothing"))
((binary_expression . (identifier) @_lhs . (operator) . (identifier) .) @nothing_equality.not
 (#match? @_lhs "!$"))

; A runtime type check that raises. One says the function is strict about what it takes;
; several say the signature is doing its checking in the body, where the caller cannot see
; it and no method table records it.
((binary_expression
   . (binary_expression . (_) . (operator) @_isa . (_) .)
   . (operator) @_or
   . (call_expression . (identifier) @_throw))
 @type_check_density
 (#eq? @_isa "isa") (#eq? @_or "||") (#eq? @_throw "throw"))

; A null guard that returns null. One is a boundary; several mean the `nothing` travels,
; and every caller downstream inherits the same guard.
((binary_expression
   . (binary_expression . (_) . (operator) @_eq . (identifier) @_n .)
   . (operator) @_and
   . (return_statement) @_r)
 @null_guard_density
 (#any-of? @_eq "===" "==") (#eq? @_n "nothing") (#eq? @_and "&&")
 (#any-of? @_r "return" "return nothing"))
((if_statement
   (binary_expression . (_) . (operator) @_eq . (identifier) @_n .)
   (block . (return_statement) @_r .))
 @null_guard_density
 (#any-of? @_eq "===" "==") (#eq? @_n "nothing")
 (#any-of? @_r "return" "return nothing"))

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently.
(try_statement) @try_density
