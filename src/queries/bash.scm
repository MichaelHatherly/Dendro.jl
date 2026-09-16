; Bash node identification. Bash has no return-statement node (`return` is a
; command) and no finally construct, so those concepts have no patterns.
; Bash control bodies are command sequences, not block nodes, so the NPath construct
; families (@loop/@switch/@ternary/@try/@case) are not wired; npath on Bash reduces to
; a sequence count. Bash has no documentation convention a reader or a doc tool agrees
; on, so @doc has no pattern either and `:undocumented_public` says nothing about a bash
; file.

(function_definition) @function

[(if_statement) (elif_clause) (for_statement) (while_statement)
 (case_item)] @decision

; The decision count's reading of a case: the arms @decision charges one apiece, and the
; case that replaces them. Bash wires no npath switch family, so these two are the only
; place the arms are named; a `*)` catch-all is a case_item, so it cancels either way.
(case_item) @switch_arm
(case_statement) @switch_stmt

(elif_clause) @continuation

[(if_statement) (for_statement) (while_statement) (case_statement)] @nesting

["&&" "||"] @short_circuit

(compound_statement) @body

(comment) @comment

(word) @name

(command) @call

; A call's target name: the command word.
(command name: (command_name (word) @callee))

[(if_statement) (case_statement)] @conditional
