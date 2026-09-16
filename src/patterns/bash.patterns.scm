; The shipped pack, realised for bash. `builtin.toml` says what each rule means; this file
; says what it looks like. A rule with no pattern here never fires for bash, which is
; ordinary: the declaration is language-independent and no grammar spells every shape.
;
; Sixteen of the eighteen have no bash pattern, which is the language rather than the
; queries. A shell function returns an exit status rather than a value, so every rule about
; what a branch returns names nothing: no boolean to return, no larger of two values to pick,
; no null to guard against. There is no `try`, no exception type, no runtime type, no
; container protocol behind a length, and no key view. What is left is the two rules that
; read the shape of the code rather than the values flowing through it.

; A rule of dashes and nothing else. A banner carrying a title is a heading and is left
; alone; this names the decoration with no content in it. A shebang is not a banner: `#!`
; opens with a character no rule of dashes contains.
((comment) @banner_comment (#match? @banner_comment "^#[ \t]*[-=*_~#]{8,}[ \t\r]*$"))

; An `elif` testing what an earlier branch already tested. The earlier branch takes every
; value that reaches the later one, so the later body never runs and one of the two
; conditions is not the one the author meant. `#structure-eq?` compares the conditions as
; trees, so a respelling is caught and two different conditions are not.
;
; An `elif` is a clause of the `if` rather than a nested statement, so the chain is flat and
; every pair in it is compared. The condition is the clause's first child rather than a named
; field, which is what the anchor pins.
((if_statement condition: (_) @_c (elif_clause . (_) @_e))
 @unreachable_branch (#structure-eq? @_c @_e))
((if_statement (elif_clause . (_) @_a) (elif_clause . (_) @_b))
 @unreachable_branch (#structure-eq? @_a @_b))
