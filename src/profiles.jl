# Language profiles. One entry per supported language, keyed by language name.

const PROFILES = Dict{Symbol,LanguageProfile}()

PROFILES[:julia] = LanguageProfile(
    :julia,
    Set(["function_definition"]),
    Set([
        "if_statement",
        "elseif_clause",
        "for_statement",
        "while_statement",
        "ternary_expression",
        "catch_clause",
    ]),
    Set(["&&", "||"]),
    Set(["if_statement", "for_statement", "while_statement", "try_statement"]),
    Set(["argument_list"]),
    Set(["block"]),
    Set(["catch_clause"]),
    Set(["line_comment", "block_comment"]),
    Set(["identifier"]),
    Set{String}(),
)

PROFILES[:python] = LanguageProfile(
    :python,
    Set(["function_definition"]),
    Set([
        "if_statement",
        "elif_clause",
        "for_statement",
        "while_statement",
        "except_clause",
        "conditional_expression",
    ]),
    Set(["and", "or"]),
    Set(["if_statement", "for_statement", "while_statement", "try_statement", "with_statement"]),
    Set(["parameters"]),
    Set(["block"]),
    Set(["except_clause"]),
    Set(["comment"]),
    Set(["identifier"]),
    Set(["pass_statement"]),
)
