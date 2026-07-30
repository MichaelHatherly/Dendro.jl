; Dendro's own pattern rules. Adding a language is data, and so is adding a rule: this
; file names shapes the concept vocabulary cannot reach, and `.dendro.toml` says what
; each one means.
;
; The bar a rule here answers to: every match has one right answer, and it is a code
; change. A shape that is merely unusual, or that a reviewer would confirm and then accept,
; costs more attention than it returns and belongs in neither this file nor a report.
; `rules.jl` already carries the shapes that need a binding or a tree walk, so nothing here
; restates `empty_catch`, `broad_catch`, `return_in_finally`, or `trivial_wrapper`.

; A `catch` that binds no exception discards what went wrong. The second pattern is the
; same pattern made more specific, so it subtracts by node identity; a tree-sitter anchor
; would miss a clause carrying a trailing comment.
(catch_clause) @empty_catch_binding
(catch_clause (identifier)) @empty_catch_binding.not

; A `catch` that binds the exception and then discards it anyway. `empty_catch` reads an
; empty body and stops there, so the shape that binds `e` and returns without ever naming
; it goes unreported, which is the one an agent writes. A body doing anything else is a
; handler; only a lone `return`, `return nothing`, or `nothing` is the error going nowhere.
;
; A clause binding nothing is `empty_catch_binding`'s to report, so each pattern requires
; the binding: one catch is one finding, and the two rules partition rather than overlap.
; Requiring it rather than subtracting an unbound clause by anchor, for the reason the note
; above gives: a comment after `catch` is a named child and defeats the anchor.
(catch_clause (identifier) (block . (return_statement) .)) @swallowed_error
((catch_clause (identifier) (block . (return_statement (_) @_ret) .)) @swallowed_error.not
 (#not-eq? @_ret "nothing"))
((catch_clause (identifier) (block . (identifier) @_only .)) @swallowed_error
 (#eq? @_only "nothing"))

; `NaN` compares unequal to everything, itself included, so a comparison against it is a
; branch that never runs. `isnan` is the question being asked.
;
; Sibling patterns match in source order, so a literal on the left of the operator needs
; its own pattern rather than falling out of the first. Every rule below reading one side
; of a `binary_expression` is written twice for that reason.
((binary_expression (operator) @_op (identifier) @_nan) @nan_comparison
 (#any-of? @_op "==" "!=" "===" "!==") (#eq? @_nan "NaN"))
((binary_expression (identifier) @_nan (operator) @_op) @nan_comparison
 (#any-of? @_op "==" "!=" "===" "!==") (#eq? @_nan "NaN"))

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

; `typeof(x) == T` is true only for the exact type, so it is false for every subtype and
; for a wrapper the caller had every right to pass. `isa` and `<:` ask the question the
; code meant. Both operand orders, since the call reads naturally either way.
;
; The other side has to be a type written down, hence the capital: comparing two types that
; both arrived as values (`typeof(x) == typeof(y)`, `stored == typeof(x)`) is asking whether
; two types are the same, which `==` answers correctly and no `isa` replaces. Naming
; convention is the only thing separating the two, and Julia's is strong enough to use.
((binary_expression . (call_expression . (identifier) @_f) . (operator) @_op . (identifier) @_t .)
 @type_equality
 (#eq? @_f "typeof") (#any-of? @_op "==" "!=") (#match? @_t "^[A-Z]"))
((binary_expression . (identifier) @_t . (operator) @_op . (call_expression . (identifier) @_f) .)
 @type_equality
 (#eq? @_f "typeof") (#any-of? @_op "==" "!=") (#match? @_t "^[A-Z]"))

; `match` returns `nothing` when the pattern does not match, so reaching into the result
; throws on the input the regex was not written for. `capture_text` in `resolve.jl` is what
; this codebase does instead.
((field_expression . (call_expression . (identifier) @_f)) @unchecked_match (#eq? @_f "match"))
((index_expression . (call_expression . (identifier) @_f)) @unchecked_match (#eq? @_f "match"))

; `1:length(x)` writes down an assumption about where `x` starts that `x` is entitled to
; break. `eachindex(x)` reads it off the container, and is what every index into `x` in the
; loop body is going to need anyway.
((for_binding (range_expression . (integer_literal) @_lo . (call_expression . (identifier) @_f)))
 @length_index_range (#eq? @_lo "1") (#eq? @_f "length"))

; `collect` builds a vector. Iterating one, or asking its length, is asking a lazy sequence
; a question it could have answered without the allocation.
((for_binding (call_expression . (identifier) @_f)) @redundant_collect (#eq? @_f "collect"))
((call_expression . (identifier) @_outer . (argument_list . (call_expression . (identifier) @_f)))
 @redundant_collect
 (#any-of? @_outer "length" "isempty" "first" "last" "sum" "maximum" "minimum")
 (#eq? @_f "collect"))

; A container with no element type is a container of `Any`: every element is stored behind
; a pointer and every read comes back untyped. `Int[]` and `Dict{String, Int}()` cost a few
; characters and say what the code already knows.
; Julia spells `Int[]` and `ref[]` with the same empty `vector_expression` an untyped `[]`
; uses, distinguished only by sitting inside an `index_expression`, so both subtract.
; `BitSet()` is absent: it takes no parameters because its elements are always `Int`, so
; the empty call is already as concrete as the type gets.
((call_expression . (identifier) @_c . (argument_list "(" . ")")) @untyped_container
 (#any-of? @_c "Dict" "IdDict" "Set" "Vector"))
(vector_expression "[" . "]") @untyped_container
(index_expression (vector_expression "[" . "]") @untyped_container.not)

; `eval` inside a function evaluates into the world age the call started in, so what it
; defines is invisible to the rest of that same call. Metaprogramming at module scope has
; no such problem, which is why the ancestor test is the rule rather than the call.
((call_expression . (identifier) @_f) @eval_in_function
 (#eq? @_f "eval") (#has-ancestor? @eval_in_function "function_definition"))
((macrocall_expression (macro_identifier (identifier) @_m)) @eval_in_function
 (#eq? @_m "eval") (#has-ancestor? @eval_in_function "function_definition"))

; A function declaring `global` reads and writes state its signature says nothing about,
; and the binding it reaches for is untyped unless it is `const`. The parameter list is
; where that value should have arrived.
((global_statement) @global_in_function
 (#has-ancestor? @global_in_function "function_definition"))

; A struct field typed abstractly is a pointer to a value stored elsewhere, so reading it
; costs a load and tells the compiler nothing about what came back. A type parameter
; (`f::F`) keeps the field concrete per instance and costs the declaration one character.
((struct_definition (block (typed_expression . (identifier) . (identifier) @_t) @abstract_field))
 (#any-of? @_t
  "Any" "Function" "AbstractString" "AbstractChar" "Number" "Real" "Integer" "AbstractFloat"
  "Signed" "Unsigned" "AbstractArray" "AbstractVector" "AbstractMatrix" "AbstractDict"
  "AbstractSet" "AbstractRange" "Array" "Dict" "Vector" "Set" "Tuple" "NamedTuple"))

; Two splats concatenated into a vector. `[a..., b...]` walks both operands element by
; element to build a result `[a; b]` names directly, and the splat form loses the element
; type where the concatenation keeps it.
;
; `out[before..., i, after...]` spreads dimensions into an index and builds no vector at
; all. It parses as the same `index_expression` a typed literal `Symbol[a..., b...]` does,
; which is a concatenation and stays reported, so the capital tells them apart as it does
; for `type_equality`: a type constructs, a value is indexed.
(vector_expression (splat_expression) (splat_expression)) @splat_concatenation
((index_expression . (identifier) @_target
  . (vector_expression (splat_expression) (splat_expression)) @splat_concatenation.not)
 (#not-match? @_target "^[A-Z]"))

; An *unnamed* numeric literal. A literal bound to a name is not magic, which is the
; whole point of the rule, so a literal standing as the whole right-hand side of an
; assignment subtracts: `threshold = 7`, `const LIMIT = 13`, and a keyword default
; `f(x = 7)` all name their number and say nothing further. A literal inside a larger
; expression still counts, since `x = 7 + 42` names the result and not the parts.
;
; 0, 1, and 2 are excluded outright: they carry their meaning in the expression around
; them, where 7 or 0.95 is a decision nobody wrote down.
(integer_literal) @magic_number
(float_literal) @magic_number
((integer_literal) @magic_number.not (#any-of? @magic_number.not "0" "1" "2"))
(assignment (operator) . (integer_literal) @magic_number.not)
(assignment (operator) . (float_literal) @magic_number.not)
