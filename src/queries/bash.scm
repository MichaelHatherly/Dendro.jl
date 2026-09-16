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
