; The shipped pack, realised for PHP. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for PHP, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Five of the pack's rules have no PHP pattern. `nothing_equality` would name `== null`, and
; `===` against null is already how the identity test is written. `type_equality` has no
; spelling short of comparing `get_class` strings, `redundant_collect` no lazy sequence a
; call would have iterated, `redundant_default` no array lookup carrying an explicit
; default, and an index loop over an array is idiomatic.
;
; An `elseif` is a clause of the `if` rather than a nested statement, so a chain is flat and
; every pair in it can be compared.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return $c` is the whole of it.
((if_statement
   body: (compound_statement . (return_statement (boolean)) .)
   alternative: (else_clause body: (compound_statement . (return_statement (boolean)) .)))
 @boolean_return)

; An `elseif` testing what an earlier branch already tested. The earlier branch takes every
; value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
((if_statement condition: (_) @_c alternative: (else_if_clause condition: (_) @_e))
 @unreachable_branch (#structure-eq? @_c @_e))
((if_statement
   alternative: (else_if_clause condition: (_) @_a)
   alternative: (else_if_clause condition: (_) @_b))
 @unreachable_branch (#structure-eq? @_a @_b))

; Comparing two values and then returning the one the comparison picked. `max` and `min` say
; it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if ($a === $b)` picks nothing.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b))
   body: (compound_statement . (return_statement (_) @_x) .)
   alternative: (else_clause body: (compound_statement . (return_statement (_) @_y) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `catch` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
;
; The caught type has to be one of the broad ones. `catch (JsonException $e) { return null; }`
; converts a named failure into a value on purpose, the same call Python's `except
; ValueError` gets.
((catch_clause
   type: (type_list (named_type (name) @_t))
   body: (compound_statement . (return_statement) @_r .))
 @swallowed_error
 (#any-of? @_t "Exception" "Throwable" "Error")
 (#match? @_r "^return([ \t]+(null|false|true|0|\\[\\]))?;?$"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if ($flag)` is how it is asked.
((binary_expression operator: ["==" "===" "!=" "!==" "<>"] right: (boolean)) @boolean_equality)
((binary_expression left: (boolean) operator: ["==" "===" "!=" "!==" "<>"]) @boolean_equality)

; `count($xs) == 0` counts every element to find out whether there are any. `empty($xs)` asks
; the question directly. Both operand orders, since the comparison reads naturally either
; way.
((binary_expression
   left: (function_call_expression function: (name) @_f)
   operator: ["==" "===" "!=" "!=="]
   right: (integer) @_z)
 @empty_check (#any-of? @_f "count" "sizeof" "strlen") (#eq? @_z "0"))
((binary_expression
   left: (integer) @_z
   operator: ["==" "===" "!=" "!=="]
   right: (function_call_expression function: (name) @_f))
 @empty_check (#any-of? @_f "count" "sizeof" "strlen") (#eq? @_z "0"))

; A value converted and immediately converted back. `intval(strval($x))` hands `intval` a
; number written out as text so it can read the number back.
((function_call_expression
   function: (name) @_o
   arguments: (arguments (argument (function_call_expression function: (name) @_i))))
 @redundant_conversion
 (#any-of? @_o "intval" "floatval" "doubleval" "boolval") (#eq? @_i "strval"))
((function_call_expression
   function: (name) @_o
   arguments: (arguments (argument (function_call_expression function: (name) @_i))))
 @redundant_conversion
 (#eq? @_o "strval") (#any-of? @_i "intval" "floatval" "doubleval" "boolval"))

; `in_array($k, array_keys($d))` builds an array of every key and scans it to ask a question
; the array answers itself. `array_key_exists($k, $d)` is the same test without the scan, and
; `isset($d[$k])` when a null value is not a member.
((function_call_expression
   function: (name) @_f
   arguments: (arguments (argument) (argument (function_call_expression function: (name) @_k))))
 @redundant_keys (#eq? @_f "in_array") (#eq? @_k "array_keys"))

; An exception class with no fields and no behaviour. The name is the whole of it, and a name
; is what the `throw` site already carries. The body has to be empty as written, so a class
; carrying even a comment is left alone.
((class_declaration
   (base_clause (name) @_base)
   body: (declaration_list) @_body)
 @empty_error_type
 (#match? @_base "(Error|Exception)$") (#match? @_body "^\\{[ \t\r\n]*\\}$"))

; A runtime type check that throws. One says the function is strict about what it takes;
; several say the signature is doing its checking in the body, where the caller cannot see it
; and the declared parameter types say nothing about it.
((if_statement
   condition: (parenthesized_expression
     (unary_op_expression operator: "!"
       argument: (parenthesized_expression (binary_expression operator: "instanceof"))))
   body: (compound_statement . (expression_statement (throw_expression)) .))
 @type_check_density)

; A null guard that returns null. One is a boundary; several mean the null travels, and every
; caller downstream inherits the same guard.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) operator: ["===" "=="] right: (null)))
   body: (compound_statement . (return_statement) @_r .))
 @null_guard_density (#match? @_r "^return([ \t]+null)?;?$"))

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently.
(try_statement) @try_density
