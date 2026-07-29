; Dendro's own pattern rules. Adding a language is data, and so is adding a rule: this
; file names shapes the concept vocabulary cannot reach, and `.dendro.toml` says what
; each one means.

; A `catch` that binds no exception discards what went wrong. The second pattern is the
; same pattern made more specific, so it subtracts by node identity; a tree-sitter anchor
; would miss a clause carrying a trailing comment.
(catch_clause) @empty_catch_binding
(catch_clause (identifier)) @empty_catch_binding.not

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
