# Language profiles. One entry per supported language, keyed by language name.
# Node types come from each grammar's parse tree, not assumption.
#
# Switch/case complexity counts each case label. Where a grammar gives the
# default branch its own node type (Go, JS, TS, PHP, Ruby) it is excluded;
# where default shares the case node (C, C++, Java) it adds one. This is a
# documented variance, not a per-language workaround.

const PROFILES = Dict{Symbol,LanguageProfile}()

PROFILES[:julia] = LanguageProfile(
    :julia;
    function_types = ["function_definition"],
    decision_types = ["if_statement", "elseif_clause", "for_statement", "while_statement",
        "ternary_expression", "catch_clause"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "while_statement", "try_statement"],
    parameter_types = ["argument_list"],
    body_types = ["block"],
    catch_types = ["catch_clause"],
    comment_types = ["line_comment", "block_comment"],
    name_types = ["identifier"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["call_expression"],
)

PROFILES[:python] = LanguageProfile(
    :python;
    function_types = ["function_definition"],
    decision_types = ["if_statement", "elif_clause", "for_statement", "while_statement",
        "except_clause", "conditional_expression"],
    short_circuit_ops = ["and", "or"],
    nesting_types = ["if_statement", "for_statement", "while_statement", "try_statement",
        "with_statement"],
    parameter_types = ["parameters"],
    body_types = ["block"],
    catch_types = ["except_clause"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    trivial_body_types = ["pass_statement"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["call"],
)

PROFILES[:bash] = LanguageProfile(
    :bash;
    function_types = ["function_definition"],
    decision_types = ["if_statement", "elif_clause", "for_statement", "while_statement",
        "case_item"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "while_statement", "case_statement"],
    body_types = ["compound_statement"],
    comment_types = ["comment"],
    name_types = ["word"],
    # Bash has no return-statement node (`return` is a command) and no finally
    # construct, so those concepts stay empty.
    call_types = ["command"],
)

PROFILES[:c] = LanguageProfile(
    :c;
    function_types = ["function_definition"],
    decision_types = ["if_statement", "for_statement", "while_statement", "do_statement",
        "case_statement", "conditional_expression"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "while_statement", "do_statement",
        "switch_statement"],
    parameter_types = ["parameter_list"],
    body_types = ["compound_statement"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    # C has no finally construct, so that concept stays empty.
    return_types = ["return_statement"],
    call_types = ["call_expression"],
)

PROFILES[:cpp] = LanguageProfile(
    :cpp;
    function_types = ["function_definition"],
    decision_types = ["if_statement", "for_statement", "range_based_for_statement",
        "while_statement", "do_statement", "case_statement", "conditional_expression",
        "catch_clause"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "range_based_for_statement",
        "while_statement", "do_statement", "switch_statement", "try_statement"],
    parameter_types = ["parameter_list"],
    body_types = ["compound_statement"],
    catch_types = ["catch_clause"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    # C++ try has no finally clause, so that concept stays empty.
    return_types = ["return_statement"],
    call_types = ["call_expression"],
)

PROFILES[:go] = LanguageProfile(
    :go;
    function_types = ["function_declaration", "method_declaration"],
    decision_types = ["if_statement", "for_statement", "expression_case", "type_case",
        "communication_case"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "expression_switch_statement",
        "type_switch_statement", "select_statement"],
    parameter_types = ["parameter_list"],
    body_types = ["block"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    # Go has no finally construct, so that concept stays empty.
    return_types = ["return_statement"],
    call_types = ["call_expression"],
)

PROFILES[:java] = LanguageProfile(
    :java;
    function_types = ["method_declaration", "constructor_declaration"],
    decision_types = ["if_statement", "for_statement", "enhanced_for_statement",
        "while_statement", "do_statement", "switch_label", "ternary_expression",
        "catch_clause"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "enhanced_for_statement",
        "while_statement", "do_statement", "switch_expression", "try_statement"],
    parameter_types = ["formal_parameters"],
    body_types = ["block"],
    catch_types = ["catch_clause"],
    comment_types = ["line_comment", "block_comment"],
    name_types = ["identifier"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["method_invocation"],
)

PROFILES[:javascript] = LanguageProfile(
    :javascript;
    function_types = ["function_declaration", "function_expression", "arrow_function",
        "method_definition", "generator_function_declaration"],
    decision_types = ["if_statement", "for_statement", "for_in_statement", "while_statement",
        "do_statement", "switch_case", "ternary_expression", "catch_clause"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "for_in_statement", "while_statement",
        "do_statement", "switch_statement", "try_statement"],
    parameter_types = ["formal_parameters"],
    body_types = ["statement_block"],
    catch_types = ["catch_clause"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["call_expression"],
)

PROFILES[:php] = LanguageProfile(
    :php;
    function_types = ["function_definition", "method_declaration"],
    decision_types = ["if_statement", "else_if_clause", "for_statement", "foreach_statement",
        "while_statement", "do_statement", "case_statement", "conditional_expression",
        "catch_clause"],
    short_circuit_ops = ["&&", "||", "and", "or"],
    nesting_types = ["if_statement", "for_statement", "foreach_statement", "while_statement",
        "do_statement", "switch_statement", "try_statement"],
    parameter_types = ["formal_parameters"],
    body_types = ["compound_statement"],
    catch_types = ["catch_clause"],
    comment_types = ["comment"],
    name_types = ["name"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["function_call_expression"],
)

# Ruby's begin/rescue keeps the handler body inline rather than in a block node,
# so swallowed-rescue detection does not fit the block model; catch_types is left
# empty and empty-rescue is not flagged.
PROFILES[:ruby] = LanguageProfile(
    :ruby;
    function_types = ["method", "singleton_method"],
    decision_types = ["if", "elsif", "unless", "while", "until", "for", "when", "rescue",
        "conditional"],
    short_circuit_ops = ["&&", "||", "and", "or"],
    nesting_types = ["if", "unless", "while", "until", "for", "case", "begin"],
    parameter_types = ["method_parameters"],
    body_types = ["body_statement"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    return_types = ["return"],
    finally_types = ["ensure"],
    call_types = ["call"],
)

PROFILES[:rust] = LanguageProfile(
    :rust;
    function_types = ["function_item"],
    decision_types = ["if_expression", "while_expression", "while_let_expression",
        "for_expression", "loop_expression", "match_arm"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_expression", "while_expression", "for_expression", "loop_expression",
        "match_expression"],
    parameter_types = ["parameters"],
    body_types = ["block"],
    comment_types = ["line_comment", "block_comment"],
    name_types = ["identifier"],
    # Rust has no finally construct, so that concept stays empty. A bare trailing
    # expression is the idiomatic return and has no node, so return_count
    # undercounts explicit `return` only by design.
    return_types = ["return_expression"],
    call_types = ["call_expression"],
)

PROFILES[:typescript] = LanguageProfile(
    :typescript;
    function_types = ["function_declaration", "function_expression", "arrow_function",
        "method_definition", "generator_function_declaration"],
    decision_types = ["if_statement", "for_statement", "for_in_statement", "while_statement",
        "do_statement", "switch_case", "ternary_expression", "catch_clause"],
    short_circuit_ops = ["&&", "||"],
    nesting_types = ["if_statement", "for_statement", "for_in_statement", "while_statement",
        "do_statement", "switch_statement", "try_statement"],
    parameter_types = ["formal_parameters"],
    body_types = ["statement_block"],
    catch_types = ["catch_clause"],
    comment_types = ["comment"],
    name_types = ["identifier"],
    return_types = ["return_statement"],
    finally_types = ["finally_clause"],
    call_types = ["call_expression"],
)
