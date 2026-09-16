; The shipped pack, realised for Java. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for Java, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Four of the pack's rules have no Java pattern. `nothing_equality` would name `== null`,
; which is how Java tests for null. `redundant_collect` has no lazy sequence a call would
; have iterated, `redundant_default` no map lookup carrying an explicit default, and an
; index loop over a list is idiomatic.
;
; An `else if` is an `if_statement` in the `alternative` field directly, with no clause node
; between, which is where this grammar differs from the C family.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((line_comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   consequence: (block . (return_statement [(true) (false)]) .)
   alternative: (block . (return_statement [(true) (false)]) .))
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

; Comparing two values and then returning the one the comparison picked. `Math.max` and
; `Math.min` say it in one call and say which of the two was meant. The operator is
; restricted to the orderings: `if (a == b)` picks nothing.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b))
   consequence: (block . (return_statement (_) @_x) .)
   alternative: (block . (return_statement (_) @_y) .))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `catch` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
;
; The caught type has to be one of the broad ones. `catch (NumberFormatException e) { return
; null; }` is a deliberate conversion of a failure into a value, the same call Python's
; `except ValueError` gets, and reporting it would cost more attention than it returns.
((catch_clause
   (catch_formal_parameter (catch_type (type_identifier) @_t))
   body: (block . (return_statement) @_r .))
 @swallowed_error
 (#any-of? @_t "Exception" "RuntimeException" "Throwable")
 (#match? @_r "^return([ \t]+(null|false|true|0))?;?$"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if (flag)` is how it is asked.
((binary_expression operator: ["==" "!="] right: [(true) (false)]) @boolean_equality)
((binary_expression left: [(true) (false)] operator: ["==" "!="]) @boolean_equality)

; `xs.size() == 0` counts every element to find out whether there are any. `xs.isEmpty()`
; asks the question directly. Both operand orders, since the comparison reads naturally
; either way.
((binary_expression
   left: (method_invocation name: (identifier) @_f arguments: (argument_list))
   operator: ["==" "!="]
   right: (decimal_integer_literal) @_z)
 @empty_check (#any-of? @_f "size" "length") (#eq? @_z "0"))
((binary_expression
   left: (decimal_integer_literal) @_z
   operator: ["==" "!="]
   right: (method_invocation name: (identifier) @_f arguments: (argument_list)))
 @empty_check (#any-of? @_f "size" "length") (#eq? @_z "0"))

; A value converted and immediately converted back. `Integer.parseInt(String.valueOf(x))`
; hands `parseInt` a number written out as text so it can read the number back.
((method_invocation
   object: (identifier) @_oc name: (identifier) @_o
   arguments: (argument_list
     (method_invocation object: (identifier) @_ic name: (identifier) @_i)))
 @redundant_conversion
 (#any-of? @_oc "Integer" "Long" "Double" "Float")
 (#any-of? @_o "parseInt" "parseLong" "parseDouble" "parseFloat")
 (#eq? @_ic "String") (#eq? @_i "valueOf"))
((method_invocation
   object: (identifier) @_oc name: (identifier) @_o
   arguments: (argument_list
     (method_invocation object: (identifier) @_ic name: (identifier) @_i)))
 @redundant_conversion
 (#eq? @_oc "String") (#eq? @_o "valueOf")
 (#any-of? @_ic "Integer" "Long" "Double" "Float")
 (#any-of? @_i "parseInt" "parseLong" "parseDouble" "parseFloat"))

; `m.keySet().contains(k)` builds a key view to ask a question the map answers itself.
; `m.containsKey(k)` is the same test without the view.
((method_invocation
   object: (method_invocation name: (identifier) @_k arguments: (argument_list))
   name: (identifier) @_c)
 @redundant_keys (#eq? @_k "keySet") (#eq? @_c "contains"))

; An exception class with no fields and no behaviour. The name is the whole of it, and a
; name is what the `throw` site already carries. The body has to be empty as written, so a
; class carrying even a comment is left alone.
((class_declaration
   superclass: (superclass (type_identifier) @_base)
   body: (class_body) @_body)
 @empty_error_type
 (#match? @_base "(Error|Exception|Throwable)$") (#match? @_body "^\\{[ \t\r\n]*\\}$"))

; `x.getClass() == T.class` is true for `T` and false for every subclass of it, so a caller
; passing a specialisation the code handles perfectly well takes the other branch.
; `instanceof` asks what the comparison meant.
((binary_expression
   left: (method_invocation name: (identifier) @_g arguments: (argument_list))
   operator: ["==" "!="]
   right: (class_literal))
 @type_equality (#eq? @_g "getClass"))
((binary_expression
   left: (class_literal)
   operator: ["==" "!="]
   right: (method_invocation name: (identifier) @_g arguments: (argument_list)))
 @type_equality (#eq? @_g "getClass"))

; A runtime type check that throws. One says the method is strict about what it takes;
; several say the signature is doing its checking in the body, where the caller cannot see
; it and the compiler cannot read it.
((if_statement
   condition: (parenthesized_expression
     (unary_expression operator: "!"
       operand: (parenthesized_expression (instanceof_expression))))
   consequence: (block . (throw_statement) .))
 @type_check_density)

; A null guard that returns null. One is a boundary; several mean the null travels, and
; every caller downstream inherits the same guard. Both body shapes, since a one-line guard
; carries its `return` without a block.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) operator: "==" right: (null_literal)))
   consequence: (block . (return_statement) @_r .))
 @null_guard_density (#match? @_r "^return([ \t]+null)?;?$"))
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) operator: "==" right: (null_literal)))
   consequence: (return_statement) @_r)
 @null_guard_density (#match? @_r "^return([ \t]+null)?;?$"))

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently. A try-with-resources counts as one: it
; is a `try` whose cleanup the language writes.
[(try_statement) (try_with_resources_statement)] @try_density
