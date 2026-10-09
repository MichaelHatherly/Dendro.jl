; Bash lexical scopes. Feeds Dendro's binding resolver: @scope marks a region,
; @definition.<kind> a name-introducing identifier, @reference a name use. Function
; names hoist to the enclosing scope so a sibling reference resolves.

; --- Scope regions ---
(program) @scope
(function_definition) @scope

; --- Function names (hoisted) ---
(function_definition name: (word) @definition.function)

; --- Local bindings ---
; An assignment binds in every node that holds one except `command`, where it is a
; prefix (`IFS= read -r line`) setting the variable for that one command's environment.
; The holders are the grammar's `_statement` contexts plus the forms that carry an
; assignment without being a statement.
(program (variable_assignment name: (variable_name) @definition.local))
(compound_statement (variable_assignment name: (variable_name) @definition.local))
(do_group (variable_assignment name: (variable_name) @definition.local))
(subshell (variable_assignment name: (variable_name) @definition.local))
(if_statement (variable_assignment name: (variable_name) @definition.local))
(elif_clause (variable_assignment name: (variable_name) @definition.local))
(else_clause (variable_assignment name: (variable_name) @definition.local))
(case_item (variable_assignment name: (variable_name) @definition.local))
(while_statement (variable_assignment name: (variable_name) @definition.local))
(list (variable_assignment name: (variable_name) @definition.local))
(pipeline (variable_assignment name: (variable_name) @definition.local))
(negated_command (variable_assignment name: (variable_name) @definition.local))
(redirected_statement (variable_assignment name: (variable_name) @definition.local))
(heredoc_redirect (variable_assignment name: (variable_name) @definition.local))
(command_substitution (variable_assignment name: (variable_name) @definition.local))
(process_substitution (variable_assignment name: (variable_name) @definition.local))
(declaration_command (variable_assignment name: (variable_name) @definition.local))
(variable_assignments (variable_assignment name: (variable_name) @definition.local))
(c_style_for_statement (variable_assignment name: (variable_name) @definition.local))
(parenthesized_expression (variable_assignment name: (variable_name) @definition.local))
(variable_assignment (variable_assignment name: (variable_name) @definition.local))

; --- References ---
; A variable use is an expansion (`$x`, `${x}`), whose `variable_name` is the
; reference; a `word` covers command names and bare arguments. An assignment's own
; `variable_name` is also a definition, so the resolver skips it as a use.
(word) @reference
(variable_name) @reference
