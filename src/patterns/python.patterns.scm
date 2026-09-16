; The shipped pack, realised for Python. `builtin.toml` says what each rule means; this
; file says what it looks like. A rule with no pattern here never fires for Python, which
; is ordinary: the declaration is language-independent and no grammar spells every shape.
;
; The bar a rule answers to is the one `.dendro/patterns/julia.patterns.scm` states: every
; match has one right answer and it is a code change. A shape a reviewer would confirm and
; then accept costs more attention than it returns.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it.
((comment) @banner_comment (#match? @banner_comment "^#[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; Each branch returns a boolean literal, so the test is being written out a second time.
; `return c` is the whole of it.
((if_statement
   consequence: (block . (return_statement [(true) (false)]) .)
   alternative: (else_clause (block . (return_statement [(true) (false)]) .)))
 @boolean_return)

; An `elif` testing what an earlier branch already tested. The earlier branch takes every
; value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
((if_statement condition: (_) @_c (elif_clause condition: (_) @_e))
 @unreachable_branch (#structure-eq? @_c @_e))
((if_statement (elif_clause condition: (_) @_a) (elif_clause condition: (_) @_b))
 @unreachable_branch (#structure-eq? @_a @_b))

; Comparing two values and then returning the one the comparison picked. `max` and `min`
; say it in one call and say which of the two was meant. The operator is restricted to the
; orderings: `if a == b: return a else: return b` picks nothing.
((if_statement
   condition: (comparison_operator (_) @_a [">" "<" ">=" "<="] (_) @_b)
   consequence: (block . (return_statement (_) @_x) .)
   alternative: (else_clause (block . (return_statement (_) @_y) .)))
 @manual_min_max
 (#structure-eq? @_a @_x) (#structure-eq? @_b @_y))

; `except Exception: return <constant>`. The error is caught, named as broadly as an
; exception can be named, and then thrown away for a value the caller cannot tell from a
; successful one.
;
; A bare `except:` and `except BaseException:` are `broad_catch`'s to report, and requiring
; the name `Exception` is what keeps the two rules partitioned rather than overlapping.
; Both spellings of the clause are written out: `except Exception as e` parses as an
; `as_pattern` where `except Exception` parses as a plain identifier.
((except_clause
   (identifier) @_e
   (block . (return_statement (_) @_r) .))
 @swallowed_error
 (#eq? @_e "Exception")
 (#any-of? @_r "None" "False" "True" "[]" "{}" "0" "()"))
((except_clause
   (as_pattern (identifier) @_e)
   (block . (return_statement (_) @_r) .))
 @swallowed_error
 (#eq? @_e "Exception")
 (#any-of? @_r "None" "False" "True" "[]" "{}" "0" "()"))

; Comparing a value against `True` or `False`. The value already answers the question the
; comparison asks, and `if flag:` is how it is asked.
((comparison_operator [(true) (false)]) @boolean_equality)

; `len(x) == 0` counts every element to find out whether there are any. `if not x:` asks
; emptiness directly, and asks it of a generator that has no length at all. Both operand
; orders, since the comparison reads naturally either way.
((comparison_operator (call function: (identifier) @_f) (integer) @_z) @empty_check
 (#eq? @_f "len") (#eq? @_z "0"))
((comparison_operator (integer) @_z (call function: (identifier) @_f)) @empty_check
 (#eq? @_f "len") (#eq? @_z "0"))

; A value converted and immediately converted back. Each pair is a round trip whose result
; is the value that went in, less whatever the middle type could not carry.
((call function: (identifier) @_o arguments: (argument_list (call function: (identifier) @_i)))
 @redundant_conversion (#eq? @_o "int") (#eq? @_i "float"))
((call function: (identifier) @_o arguments: (argument_list (call function: (identifier) @_i)))
 @redundant_conversion (#eq? @_o "str") (#eq? @_i "int"))
((call
   function: (attribute attribute: (identifier) @_o)
   arguments: (argument_list (call function: (attribute attribute: (identifier) @_i))))
 @redundant_conversion (#eq? @_o "loads") (#eq? @_i "dumps"))

; `k in d.keys()` builds a view to ask a question the mapping answers itself. `k in d` is
; the same test without the view.
((comparison_operator "in" (call function: (attribute attribute: (identifier) @_k)))
 @redundant_keys (#eq? @_k "keys"))

; `list(...)` materialises a sequence the surrounding expression would have iterated. The
; allocation buys nothing and costs the whole sequence at once.
((call function: (identifier) @_l arguments: (argument_list (call function: (identifier) @_f)))
 @redundant_collect (#eq? @_l "list") (#any-of? @_f "map" "filter" "zip" "enumerate" "reversed"))
((call function: (identifier) @_l arguments: (argument_list (call function: (attribute attribute: (identifier) @_m))))
 @redundant_collect (#eq? @_l "list") (#any-of? @_m "keys" "values" "items"))
((for_statement right: (call function: (identifier) @_l)) @redundant_collect (#eq? @_l "list"))

; `for i in range(len(x))` loops over positions to reach elements. `for item in x` reaches
; them, and `enumerate(x)` reaches them with the position when the position is wanted too.
((for_statement right: (call function: (identifier) @_r arguments: (argument_list (call function: (identifier) @_l))))
 @length_index_range (#eq? @_r "range") (#eq? @_l "len"))

; `d.get(k, None)` passes the default `get` already has. The argument says a decision was
; made where none was.
((call function: (attribute attribute: (identifier) @_g) arguments: (argument_list (_) (none)))
 @redundant_default (#eq? @_g "get"))

; An exception class with no fields and no behaviour. The name is the whole of it, and a
; name is what the `raise` site already carries.
((class_definition
   superclasses: (argument_list (identifier) @_base)
   body: (block . [(pass_statement) (expression_statement [(ellipsis) (string)])] .))
 @empty_error_type
 (#match? @_base "(Error|Exception|Warning)$"))
((class_definition
   superclasses: (argument_list (identifier) @_base)
   body: (block . (expression_statement (string)) . [(pass_statement) (expression_statement (ellipsis))] .))
 @empty_error_type
 (#match? @_base "(Error|Exception|Warning)$"))

; `type(x) == T` is true for `T` and false for every subclass of it, so a caller passing a
; specialisation the code handles perfectly well takes the other branch. `isinstance` asks
; what the comparison meant. Both operand orders, and the other side has to be a name
; rather than a second `type(...)`, since comparing two types that both arrived as values
; is a question `==` answers correctly.
((comparison_operator (call function: (identifier) @_t) (identifier)) @type_equality
 (#eq? @_t "type"))
((comparison_operator (identifier) (call function: (identifier) @_t)) @type_equality
 (#eq? @_t "type"))

; `== None` asks a value whether it compares equal to nothing, and a class with its own
; `__eq__` answers however it likes. `is None` asks identity, which is what the code meant.
((comparison_operator "==" (none)) @nothing_equality)
((comparison_operator "!=" (none)) @nothing_equality)
((comparison_operator (none) "==") @nothing_equality)
((comparison_operator (none) "!=") @nothing_equality)

; A runtime type check that raises. One says the function is strict about what it takes;
; several say the signature is doing its checking in the body, where the caller cannot see
; it and the type checker cannot read it.
((if_statement
   condition: (not_operator (call function: (identifier) @_f))
   consequence: (block . (raise_statement) .))
 @type_check_density (#eq? @_f "isinstance"))

; A null guard that returns null. One is a boundary; several mean the null travels, and
; every caller downstream inherits the same guard.
((if_statement
   condition: (comparison_operator (_) (none))
   consequence: (block . (return_statement) @_r .))
 @null_guard_density (#match? @_r "^return(\\s+None)?$"))

; A `try` block. One is error handling; several in one definition means the definition is
; several pieces of work that each fail differently.
(try_statement) @try_density
