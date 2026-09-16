; The shipped pack, realised for Go. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for Go, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Eleven of the pack's rules have no Go pattern. Go returns errors rather than raising them,
; so `try_density`, `swallowed_error` and `type_check_density` name nothing.
; `nothing_equality` would name `== nil`, which is how Go tests for nil. `empty_check` would
; name `len(xs) == 0`, which is how Go asks whether a slice or map is empty: the rule says a
; count was asked where emptiness was the question, and in Go the count is the question.
; The rest have no spelling here: no key view, no lazy sequence to materialise, no map
; lookup carrying an explicit default, no exception type, no runtime type to compare, and an
; index loop over a slice is idiomatic.
;
; A Go block holds a `statement_list` rather than its statements directly, so every rule
; reading "the block holds nothing but this" goes through one. An `else if` is an
; `if_statement` in the `alternative` field, with no clause node between.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   consequence: (block (statement_list . (return_statement (expression_list . [(true) (false)] .)) .))
   alternative: (block (statement_list . (return_statement (expression_list . [(true) (false)] .)) .)))
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
   alternative: (if_statement condition: (_) @_e))
 @unreachable_branch (#structure-eq? @_c @_e))

; Comparing two values and then returning the one the comparison picked. `max` and `min` say
; it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if a == b` picks nothing.
((if_statement
   condition: (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b)
   consequence: (block (statement_list . (return_statement (expression_list . (_) @_x .)) .))
   alternative: (block (statement_list . (return_statement (expression_list . (_) @_y .)) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if flag` is how it is asked.
((binary_expression operator: ["==" "!="] right: [(true) (false)]) @boolean_equality)
((binary_expression left: [(true) (false)] operator: ["==" "!="]) @boolean_equality)

; A value converted and immediately converted back. `strconv.Atoi(strconv.Itoa(x))` hands
; `Atoi` a number written out as text so it can read the number back.
((call_expression
   function: (selector_expression field: (field_identifier) @_o)
   arguments: (argument_list
     (call_expression function: (selector_expression field: (field_identifier) @_i))))
 @redundant_conversion
 (#any-of? @_o "Atoi" "ParseInt" "ParseFloat") (#any-of? @_i "Itoa" "FormatInt" "FormatFloat"))

; A nil guard that returns nil. One is a boundary; several mean the nil travels, and every
; caller downstream inherits the same guard. A `return nil, err` says what went wrong and is
; left alone.
((if_statement
   condition: (binary_expression left: (_) operator: "==" right: (nil))
   consequence: (block (statement_list . (return_statement) @_r .)))
 @null_guard_density (#match? @_r "^return([ \t]+nil)?$"))
