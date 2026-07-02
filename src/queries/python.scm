; Python node identification. Each pattern tags a construct Dendro measures with a
; capture naming the concept.

(function_definition) @function

[(if_statement) (elif_clause) (for_statement) (while_statement)
 (except_clause) (conditional_expression)] @decision

(elif_clause) @continuation

[(if_statement) (for_statement) (while_statement) (try_statement)
 (with_statement)] @nesting

; `and` and `or` are anonymous keyword tokens.
["and" "or"] @short_circuit

(parameters) @parameter

; A parameter's name identifier: plain, typed, defaulted, and splat forms. Lambda
; parameters are not tagged; a lambda is not a unit, so its names belong to no
; measured signature.
(parameters [
  (identifier) @parameter_name
  (typed_parameter . (identifier) @parameter_name)
  (default_parameter name: (identifier) @parameter_name)
  (typed_default_parameter name: (identifier) @parameter_name)
  (list_splat_pattern (identifier) @parameter_name)
  (dictionary_splat_pattern (identifier) @parameter_name)
])

(block) @body

(except_clause) @catch

; A handler broad enough to swallow interrupts and exits: a bare `except:` (no
; value at all), or `except BaseException`, plain or `as`-aliased. `except
; Exception` is merely wide and not tagged.
((except_clause) @broad_catch (#match? @broad_catch "^except\\s*:"))
(except_clause value: (identifier) @broad_catch (#eq? @broad_catch "BaseException"))
(except_clause value: (as_pattern . (identifier) @broad_catch) (#eq? @broad_catch "BaseException"))

(comment) @comment

(identifier) @name

(pass_statement) @trivial_body

(return_statement) @return

(finally_clause) @finally

(call) @call

[(comparison_operator) (boolean_operator) (binary_operator)] @binary_expr

[(if_statement) (match_statement)] @conditional

; NPath construct families.
[(for_statement) (while_statement)] @loop
(match_statement) @switch
(case_clause) @case
(conditional_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (raise_statement)] @terminal
