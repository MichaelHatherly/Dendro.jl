; The shipped pack, realised for JavaScript. `builtin.toml` says what each rule means; this
; file says what it looks like. A rule with no pattern here never fires for JavaScript,
; which is ordinary: the declaration is language-independent and no grammar spells every
; shape.
;
; Five of the pack's rules have no JavaScript pattern. `nothing_equality` would name `==
; null`, which is the deliberate loose check that catches `undefined` too. `type_equality`
; and `length_index_range` name the idioms: `typeof x === "string"` is how the question is
; asked, and the index loop is how an array is walked. `redundant_collect` has no standard
; lazy sequence to materialise, and `redundant_default` no `get` with a default to pass.
;
; A JavaScript `if` wraps its condition in a `parenthesized_expression`, so every rule
; reading a condition goes through one, and `else if` is an `else_clause` holding another
; `if_statement` rather than a clause of its own.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^//[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   consequence: (statement_block . (return_statement [(true) (false)]) .)
   alternative: (else_clause (statement_block . (return_statement [(true) (false)]) .)))
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

; Comparing two values and then returning the one the comparison picked. `Math.max` and
; `Math.min` say it in one call and say which of the two was meant. The operator is
; restricted to the orderings: `if (a === b)` picks nothing.
((if_statement
   condition: (parenthesized_expression
     (binary_expression left: (_) @_a operator: [">" "<" ">=" "<="] right: (_) @_b))
   consequence: (statement_block . (return_statement (_) @_x) .)
   alternative: (else_clause (statement_block . (return_statement (_) @_y) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; A `catch` whose body only returns. The error was caught and then thrown away for a value
; the caller cannot tell from a successful one. A body doing anything else is a handler.
;
; JavaScript names no exception type on a `catch`, so there is no narrow clause to leave
; alone the way Python's `except ValueError` is left alone. What partitions this rule from
; a real handler is the body and nothing else.
((catch_clause body: (statement_block . (return_statement) @_r .)) @swallowed_error
 (#match? @_r "^return([ \t]+(null|undefined|false|true|0|\\[\\]|\\{\\}))?;?$"))

; Comparing a value against `true` or `false`. The value already answers the question the
; comparison asks, and `if (flag)` is how it is asked.
((binary_expression operator: ["==" "===" "!=" "!=="] right: [(true) (false)]) @boolean_equality)
((binary_expression left: [(true) (false)] operator: ["==" "===" "!=" "!=="]) @boolean_equality)

; `xs.length === 0` counts every element to find out whether there are any. `if (!xs.length)`
; asks emptiness directly. Both operand orders, since the comparison reads naturally either
; way.
((binary_expression
   left: (member_expression property: (property_identifier) @_p)
   operator: ["==" "===" "!=" "!=="]
   right: (number) @_z)
 @empty_check (#eq? @_p "length") (#eq? @_z "0"))
((binary_expression
   left: (number) @_z
   operator: ["==" "===" "!=" "!=="]
   right: (member_expression property: (property_identifier) @_p))
 @empty_check (#eq? @_p "length") (#eq? @_z "0"))

; A value converted and immediately converted back. `parseInt(String(x))` hands `parseInt` a
; number written out as text so it can read the number back.
((call_expression
   function: (identifier) @_o
   arguments: (arguments (call_expression function: (identifier) @_i)))
 @redundant_conversion
 (#any-of? @_o "parseInt" "parseFloat" "Number") (#eq? @_i "String"))
((call_expression
   function: (identifier) @_o
   arguments: (arguments (call_expression function: (identifier) @_i)))
 @redundant_conversion
 (#eq? @_o "String") (#any-of? @_i "parseInt" "parseFloat" "Number"))

; `Object.keys(o).includes(k)` builds an array of every key and scans it to ask a question
; the object answers itself. `Object.hasOwn(o, k)` is the same test without the array.
((call_expression
   function: (member_expression
     object: (call_expression
       function: (member_expression object: (identifier) @_obj property: (property_identifier) @_keys))
     property: (property_identifier) @_has))
 @redundant_keys
 (#eq? @_obj "Object") (#eq? @_keys "keys") (#eq? @_has "includes"))

; An error class with no fields and no behaviour. The name is the whole of it, and a name is
; what the `throw` site already carries. The body has to be empty as written, so a class
; carrying even a comment is left alone.
((class_declaration
   (class_heritage (identifier) @_base)
   body: (class_body) @_body)
 @empty_error_type
 (#match? @_base "(Error|Exception)$") (#match? @_body "^\\{[ \t\r\n]*\\}$"))

; A runtime type check that throws. One says the function is strict about what it takes;
; several say the signature is doing its checking in the body, where no caller and no type
; checker can read it.
((if_statement
   condition: (parenthesized_expression
     (unary_expression operator: "!"
       argument: (parenthesized_expression (binary_expression operator: "instanceof"))))
   consequence: (statement_block . (throw_statement) .))
 @type_check_density)

; A null guard that returns null. One is a boundary; several mean the null travels, and
; every caller downstream inherits the same guard. Both body shapes, since a one-line guard
; carries its `return` without a block.
((if_statement
   condition: (parenthesized_expression
     (binary_expression operator: ["==" "==="] right: (null)))
   consequence: (statement_block . (return_statement) @_r .))
 @null_guard_density (#match? @_r "^return([ \t]+(null|undefined))?;?$"))
((if_statement
   condition: (parenthesized_expression
     (binary_expression operator: ["==" "==="] right: (null)))
   consequence: (return_statement) @_r)
 @null_guard_density (#match? @_r "^return([ \t]+(null|undefined))?;?$"))

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently.
(try_statement) @try_density
