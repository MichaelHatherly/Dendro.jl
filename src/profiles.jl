# Supported languages, keyed by language name. Each maps to its tree-sitter query
# in `src/queries/<name>.scm`, where the node types for every measured construct
# live. `haskey(PROFILES, lang)` gates whether Dendro analyses a file.
#
# Switch/case complexity counts each case label. Where a grammar gives the default
# branch its own node type (Go, JS, TS, PHP, Ruby) it is excluded from the
# `@decision` capture; where default shares the case node (C, C++, Java) it adds
# one. This is a documented variance, not a per-language workaround.

const PROFILES = Dict{Symbol, LanguageProfile}(
    name => LanguageProfile(name) for name in (
            :julia, :python, :bash, :c, :cpp, :go, :java,
            :javascript, :php, :ruby, :rust, :typescript,
        )
)
