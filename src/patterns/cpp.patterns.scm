; The shipped pack, realised for C++. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for C++, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Seven of the pack's rules have no C++ pattern. A key view, a dictionary `get` with a
; default, a lazy sequence to materialise and a runtime type to compare against have no
; standard spelling here, an index loop over a container is idiomatic, and an exception
; class carrying nothing but a name is the ordinary way to derive from `std::exception`.
;
; C++ wraps an `if` condition in a `condition_clause` where C uses a
; `parenthesized_expression`, so every rule reading a condition goes through one.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t]*$"))

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

; Comparing two values and then returning the one the comparison picked. `std::max` and
; `std::min` say it in one call and say which of the two was meant. The operator is
; restricted to the orderings: `if (a == b)` picks nothing.
((if_statement
   condition: (condition_clause value:
     (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b))
   consequence: (compound_statement . (return_statement (_) @_x) .)
   alternative: (else_clause (compound_statement . (return_statement (_) @_y) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `catch` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
;
; The clause has to name a type. `catch (...)` parses with an empty parameter list and is
; `broad_catch`'s to report, which is what keeps the two rules partitioned rather than
; overlapping.
((catch_clause
   parameters: (parameter_list (parameter_declaration))
   body: (compound_statement . (return_statement) @_r .))
 @swallowed_error
 (#match? @_r "^return([ \t]+(nullptr|NULL|false|true|0|\\{\\}))?;?$"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if (flag)` is how it is asked.
((binary_expression operator: ["==" "!="] right: [(true) (false)]) @boolean_equality)
((binary_expression left: [(true) (false)] operator: ["==" "!="]) @boolean_equality)

; `v.size() == 0` counts every element to find out whether there are any. `v.empty()` asks
; the question directly, and asks it in constant time of a container whose `size` is not.
; Both operand orders, since the comparison reads naturally either way.
((binary_expression
   left: (call_expression
     function: (field_expression field: (field_identifier) @_f)
     arguments: (argument_list))
   operator: ["==" "!="]
   right: (number_literal) @_z)
 @empty_check (#any-of? @_f "size" "length") (#eq? @_z "0"))
((binary_expression
   left: (number_literal) @_z
   operator: ["==" "!="]
   right: (call_expression
     function: (field_expression field: (field_identifier) @_f)
     arguments: (argument_list)))
 @empty_check (#any-of? @_f "size" "length") (#eq? @_z "0"))

; A value converted and immediately converted back. `std::stoi(std::to_string(x))` hands
; `stoi` a number written out as text so it can read the number back. The name is read past
; whatever namespace it was reached through, so the `using namespace std` spelling reads the
; same.
((call_expression
   function: (_) @_o
   arguments: (argument_list (call_expression function: (_) @_i)))
 @redundant_conversion
 (#match? @_o "(^|::)(stoi|stol|stoll|stod|stof)$") (#match? @_i "(^|::)to_string$"))
((call_expression
   function: (_) @_o
   arguments: (argument_list (call_expression function: (_) @_i)))
 @redundant_conversion
 (#match? @_o "(^|::)to_string$") (#match? @_i "(^|::)(stoi|stol|stoll|stod|stof)$"))

; A runtime type check that throws. One says the function is strict about what it takes;
; several say the signature is doing its checking in the body, where no caller and no
; overload set records it.
((if_statement
   condition: (condition_clause value:
     (binary_expression
       left: (call_expression function: (template_function name: (identifier) @_c))
       operator: "=="
       right: (null)))
   consequence: (compound_statement . (throw_statement) .))
 @type_check_density (#eq? @_c "dynamic_cast"))

; A null guard that returns null. One is a boundary; several mean the null travels, and
; every caller downstream inherits the same guard. Both body shapes, since a one-line guard
; carries its `return` without a block.
((if_statement
   condition: (condition_clause value:
     (binary_expression left: (_) operator: "==" right: (null)))
   consequence: (compound_statement . (return_statement (null)) .))
 @null_guard_density)
((if_statement
   condition: (condition_clause value:
     (binary_expression left: (_) operator: "==" right: (null)))
   consequence: (return_statement (null)))
 @null_guard_density)

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently.
(try_statement) @try_density
