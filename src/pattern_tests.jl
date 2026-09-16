# Testing a rule against fixtures.
#
# Everything else in this feature catches a rule that is malformed. Tree-sitter catches a
# node type the grammar lacks, the predicate allowlist catches a predicate that would reject
# every match, the declared-rule check catches a typo'd capture, and the zero-match report
# catches a rule that never fires. None of them catches a rule that fires on the wrong
# thing.
#
# A fixture pins both directions. A line marked `dendro-expect: <rule>` must be reported by
# that rule; a line not marked must not be. Checking for false positives is the point:
# asserting only that a rule matched something would pass for a rule matching everything.
#
# For the rules Dendro ships this is the only check left. Every one of them declares
# `guard = true`, so the zero-match report exempts them, and a shipped rule that stops
# matching after a grammar bump would read as a clean codebase everywhere. The fixtures
# under `test/patterns/tests/` are what catches that, and only Dendro's own CI runs them.

# An expectation marker in a fixture comment: `dendro-expect: rule[, rule]`. Parallels
# `DIRECTIVE_RE` in `suppress.jl`, which is the same idea pointed the other way, and read
# from the start of a comment for the same reason: a fixture that explains what it marks
# names its own rules in prose, and prose is not a marker.
const EXPECT_RE = r"^[\s#/*;=!<>-]*dendro-expect\b(?:\s*:\s*([\w,\s]+))?"m

"""
    PatternTestFailure

One disagreement between a fixture and what a rule did: `file` and `line` locate it, `rule`
names the rule, and `kind` is `:missed` (a marked line the rule did not report) or
`:unexpected` (an unmarked line it did).
"""
struct PatternTestFailure
    file::String
    line::Int
    rule::Symbol
    kind::Symbol
end

function Base.show(io::IO, f::PatternTestFailure)
    what = f.kind === :missed ? "expected but not matched" : "matched but not expected"
    return print(io, f.file, ":", f.line, "  ", f.rule, "  ", what)
end

# The rules a fixture line expects, read off the comment nodes rather than the raw text so
# a marker inside a string literal is not mistaken for one. `suppressions` reads its
# directives the same way and for the same reason.
function expectations(index::QueryIndex)
    out = Dict{Int, Set{Symbol}}()
    for node in index.comment.nodes
        m = match(EXPECT_RE, TreeSitter.slice(index.source, node))
        m === nothing && continue
        # `capture_text` narrows the `Union{Nothing, SubString}` a match yields, which the
        # zero-tolerance JET gate reads even where the pattern makes the group required.
        listed = capture_text(m, 1)
        names = listed === nothing ? Set{Symbol}() :
            Set(Symbol(strip(t)) for t in split(listed, r"[,\s]+"; keepempty = false))
        line = marked_line(index.source, node)
        out[line] = union(get(out, line, Set{Symbol}()), names)
    end
    return out
end

# The line a marker describes: its own when it trails code, the one under it when it has
# the line to itself. A rule whose match is a comment forces the second reading, since a
# comment carries no trailing comment: `banner_comment` could be pinned no other way.
function marked_line(source::String, node::TreeSitter.Node)
    from, _ = TreeSitter.byte_range(node)
    return line_of(node) + (starts_its_line(source, from) ? 1 : 0)
end

# True when nothing but whitespace precedes byte `from` on its line.
function starts_its_line(source::String, from::Int)
    i = prevind(source, from)
    while i >= firstindex(source)
        c = source[i]
        c == '\n' && return true
        isspace(c) || return false
        i = prevind(source, i)
    end
    return true
end

"""
    check_patterns(paths; config=nothing, fixtures=nothing) -> Vector{PatternTestFailure}

Run every declared pattern rule against the fixtures in its pattern directories and report
where a fixture and the rule disagree.

Fixtures live in a `tests/` folder beside the queries, one file per language, and mark the
lines a rule must match with a `dendro-expect: <rule>` comment. A marked line the rule did
not match is a miss; an unmarked line it did match is a false positive. Both fail.

A marker trailing code names that line. A marker with the line to itself names the line
under it, which is the only way to pin a rule whose match is a comment.

What a fixture pins is what the *query* matched, for either kind of rule. A scalar rule's
band and percentile are Dendro's own scoring and are tested elsewhere, so a scalar fixture
marks the lines its occurrences sit on exactly as a flag fixture does.

`fixtures` names the directories to search for those `tests/` folders instead of the
pattern directories. The queries still come from the cascade, so this moves where the
fixtures live and nothing else. A rule shipped inside the package needs it: a fixture is
deliberately bad source, and source under `src/` is what `errors` scans.

A rule with no fixture is not a failure. Requiring one would be friction on writing a
two-line house rule, and the zero-match report already catches the rule that never fires at
all.
"""
function check_patterns(paths; config = nothing, fixtures = nothing)
    roots::Vector{String} = paths isa AbstractString ? [paths] : collect(String, paths)
    cfg::Config = config === nothing ? discover_config(roots) : config
    out = PatternTestFailure[]
    profiles = resolve_profiles(cfg)
    dirs = pattern_dirs(cfg, roots)
    fixture_dirs::Vector{String} = fixtures === nothing ? dirs : collect(String, fixtures)
    for dir in fixture_dirs, (lang, profile) in profiles
        fixture = fixture_file(dir, lang, profiles)
        fixture === nothing && continue
        append!(out, check_fixture(fixture, profile, dirs, cfg.patterns))
    end
    return out
end

# The fixture file for one language: `tests/<lang>.<ext>` beside the queries, using the
# first extension the language claims.
function fixture_file(dir::AbstractString, lang::Symbol, profiles::Dict{Symbol, LanguageProfile})
    for ext in extensions_for(lang, profiles)
        path = joinpath(dir, "tests", "$(lang).$(ext)")
        isfile(path) && return path
    end
    return nothing
end

# The extensions a language claims, from its profile when it registers its own and from the
# built-in table otherwise.
function extensions_for(lang::Symbol, profiles::Dict{Symbol, LanguageProfile})
    profile = get(profiles, lang, nothing)
    profile === nothing && return String[]
    isempty(profile.extensions) || return profile.extensions
    return String[e for (e, l) in EXTENSIONS if l === lang]
end

# Compare one fixture against every rule with a query for its language.
function check_fixture(
        path::AbstractString, profile::LanguageProfile, dirs::Vector{String}, specs::Vector{PatternSpec}
    )
    source = read(path, String)
    tree = parse_source(profile, source)
    index = build_index(tree, profile.name, source, query_for(profile), scopes_query_for(profile))
    index_all_patterns!(index, tree, pattern_queries(profile, dirs, specs), source)

    expected = expectations(index)
    out = PatternTestFailure[]
    for rule in sort!(collect(keys(index.patterns)))
        actual = Set(line_of(n) for n in pattern_hits(index, rule))
        want = Set(line for (line, rules) in expected if rule in rules)
        for line in sort!(collect(setdiff(want, actual)))
            push!(out, PatternTestFailure(path, line, rule, :missed))
        end
        for line in sort!(collect(setdiff(actual, want)))
            push!(out, PatternTestFailure(path, line, rule, :unexpected))
        end
    end
    return out
end
