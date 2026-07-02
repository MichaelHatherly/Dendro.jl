; Julia lexical scopes. A second query feeding Dendro's binding resolver: @scope
; marks a region, @definition.<kind> a name-introducing identifier, @reference a
; name use. Function, type, and macro names (@definition.function/struct/macro)
; bind in the enclosing scope so a sibling reference resolves; the resolver hoists
; them. Parameters are not captured: a function's parameters are never shared
; across functions, so they form no cohesion edge, and an unbound parameter
; reference is the correct outcome. Node types match tree-sitter-julia.

; --- Scope regions ---
(source_file) @scope
(module_definition) @scope
(function_definition) @scope
(macro_definition) @scope
(struct_definition) @scope
(abstract_definition) @scope
(for_statement) @scope
(while_statement) @scope
(let_statement) @scope
(do_clause) @scope
(comprehension_expression) @scope
(generator) @scope

; --- Function and macro names (hoisted to the enclosing scope) ---
(function_definition (signature (call_expression . (identifier) @definition.function)))
(function_definition (signature (where_expression (call_expression . (identifier) @definition.function))))
(function_definition (signature (typed_expression (call_expression . (identifier) @definition.function))))
(function_definition (signature (where_expression (typed_expression (call_expression . (identifier) @definition.function)))))
(function_definition (signature (typed_expression (where_expression (call_expression . (identifier) @definition.function)))))
(macro_definition (signature (call_expression . (identifier) @definition.macro)))

; Short-form `f(x) = ...`: the name is the first identifier of the signature call,
; anchored to the assignment's first child so a plain `z = ...` never matches here.
(assignment . (call_expression . (identifier) @definition.function))
(assignment . (typed_expression . (call_expression . (identifier) @definition.function)))
(assignment . (where_expression . (call_expression . (identifier) @definition.function)))
(assignment . (where_expression . (typed_expression . (call_expression . (identifier) @definition.function))))
(assignment . (typed_expression . (where_expression . (call_expression . (identifier) @definition.function))))

; --- Type names (hoisted), across plain, parametric, and subtype heads ---
(struct_definition (type_head . (identifier) @definition.struct))
(struct_definition (type_head . (parametrized_type_expression . (identifier) @definition.struct)))
(struct_definition (type_head . (binary_expression . (identifier) @definition.struct)))
(struct_definition (type_head . (binary_expression . (parametrized_type_expression . (identifier) @definition.struct))))
(abstract_definition (type_head . (identifier) @definition.struct))
(abstract_definition (type_head . (parametrized_type_expression . (identifier) @definition.struct)))
(abstract_definition (type_head . (binary_expression . (identifier) @definition.struct)))
(abstract_definition (type_head . (binary_expression . (parametrized_type_expression . (identifier) @definition.struct))))

; --- const and local bindings ---
; Two binding kinds mirror Julia's scope rule. A `for`/`let` head always binds a
; fresh variable, `definition.local`; a statement assignment binds a fresh
; variable only when no enclosing local carries the name, otherwise it rebinds
; that one, `definition.assign`. The resolver treats both as definitions;
; `shadowed_variables` reads the split, since only a fresh-binding form can hide
; an enclosing name.
(const_statement (assignment . (identifier) @definition.const))
(for_binding . (identifier) @definition.local)
(let_statement (assignment . (identifier) @definition.local))
; A statement-position assignment: one directly under a source file or a block.
; Its first child is the bound identifier; short-form defs have a call_expression
; first, so they never match here. The statement anchor keeps a call-site keyword
; argument (`sort!(xs; by = f)`) and a NamedTuple field (`(added = true,)`) from
; reading as bindings: both are assignment-shaped, neither binds a name.
(source_file (assignment . (identifier) @definition.assign))
(block (assignment . (identifier) @definition.assign))

; --- References: every identifier use ---
(identifier) @reference
