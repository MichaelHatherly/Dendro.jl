; Bash node identification. Bash has no return-statement node (`return` is a
; command) and no finally construct, so those concepts have no patterns.

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

[(if_statement) (case_statement)] @conditional
