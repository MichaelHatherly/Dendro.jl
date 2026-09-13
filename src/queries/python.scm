; Python node identification. Each pattern tags a construct Dendro measures with a
; capture naming the concept.

(function_definition) @function

[(if_statement) (elif_clause) (for_statement) (while_statement)
 (except_clause) (conditional_expression)] @decision

; The decision count's reading of a match: the arms, and the match that replaces them.
; Python is the one language where @decision charges nothing for an arm, so subtracting
; them takes nothing back and the match's one charge is arithmetic the cyclomatic count
; lacks: `cyclomatic_modified` reads one higher than `cyclomatic` on a python match.
(case_clause) @switch_arm
(match_statement) @switch_stmt

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
; Exception` is merely wide and not tagged. The clause is what is tagged, so
; `broad_catches` can read its body; `@_exc` anchors the text test and names no concept.
((except_clause) @broad_catch (#match? @broad_catch "^except\\s*:"))
((except_clause value: (identifier) @_exc) @broad_catch (#eq? @_exc "BaseException"))
((except_clause value: (as_pattern . (identifier) @_exc)) @broad_catch (#eq? @_exc "BaseException"))

; A statement that throws, so a handler ending in one passes its error on.
(raise_statement) @raise

(comment) @comment

; A docstring is the first statement of a body, and documents the definition that body
; belongs to. A comment above the `def` is not one, whatever it says.
(function_definition body: (block . (expression_statement (string) @doc)))
(class_definition body: (block . (expression_statement (string) @doc)))

; A method decorated `@override` or `@typing.override` inherits the overridden method's
; docstring, which is what Sphinx and readers show for one with none of its own. The
; decorator is a sibling of the `def` inside the decorated definition, so that is the node.
((decorated_definition (decorator [(identifier) @_n (attribute attribute: (identifier) @_n)]))
  @inherits_doc (#eq? @_n "override"))

(identifier) @name

(pass_statement) @trivial_body

(return_statement) @return

(finally_clause) @finally

(call) @call

; A call's target name: the called identifier, or a method call's final name.
(call function: (identifier) @callee)
(call function: (attribute attribute: (identifier) @callee))

[(comparison_operator) (boolean_operator) (binary_operator)] @binary_expr

[(if_statement) (match_statement)] @conditional

; NPath construct families.
[(for_statement) (while_statement)] @loop
(match_statement) @switch
(case_clause) @case
(conditional_expression) @ternary
(try_statement) @try

[(return_statement) (break_statement) (continue_statement) (raise_statement)] @terminal

; --- Class-level cohesion -------------------------------------------------
; The container owning methods and the state they share.
(class_definition) @class

; The class's declared name, so a finding about the class names the class. Without it
; the lexical scan would reach the first method's name instead.
(class_definition name: (identifier) @def_name)

; A field use: an attribute of the instance the method received. Use sites are the whole
; of what a cohesion reading needs, so no declaration is captured. `@_self` anchors the
; text test and names no concept.
(attribute object: (identifier) @_self attribute: (identifier) @field
  (#any-of? @_self "self" "cls"))

; `__init__` assigns every field a class has, so leaving it among the methods would read
; every class as one concern.
((function_definition name: (identifier) @_init) @constructor (#eq? @_init "__init__"))
