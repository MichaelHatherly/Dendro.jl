# User-authored lint rules as a second query family. `<lang>.scm` captures name the
# concepts every metric reads, a closed set. A `<lang>.patterns.scm` capture names a
# *rule*, an open set written against concrete grammar node types on purpose, since
# being language-specific is the point. The two never merge: merging takes `dispatch!`'s
# closure with it and metric code starts special-casing languages.
#
# A rule is declared once in `.dendro.toml`, language-independently, and realised per
# language by a query. The declaration carries what the finding says and how loud it is;
# the query carries the shape. [`PatternSpec`](@ref) is the declaration and lives in
# `rules.jl` beside `Rule`, since `Config` holds a vector of them; everything here is what
# turns one into findings.

# Coerce a TOML value naming one of a fixed set of symbols. Unlike an unknown key, which
# warns and is dropped, a bad value here is an error: the author clearly meant to set it,
# and guessing which of two severities they wanted would be worse than stopping.
function pattern_symbol(value, allowed::Tuple{Vararg{Symbol}}, key::String, rule::String, source)::Symbol
    value isa AbstractString || config_error("`$key` for pattern `$rule` in $source must be a string, got $value")
    sym = Symbol(value)
    sym in allowed && return sym
    names = join(("`$a`" for a in allowed), ", ")
    return config_error("`$key` for pattern `$rule` in $source must be one of $names, got `$value`")
end

# Apply one `[patterns.<name>]` table. Only `message` is required; `severity`, `kind`, and
# `guard` default, and `band` is required by a scalar and rejected on a flag. An unknown key
# warns and is dropped, as a band does.
function apply_pattern!(acc, name::String, table::Dict{String, Any}, source)
    message = ""
    severity = :warn
    kind = :flag
    band = nothing
    guard = false
    for (key, value) in table
        if key == "message"
            message = config_string(value, "patterns.$name.$key", source)
        elseif key == "severity"
            severity = pattern_symbol(value, PATTERN_SEVERITIES, key, name, source)
        elseif key == "kind"
            kind = pattern_symbol(value, PATTERN_KINDS, key, name, source)
        elseif key == "band"
            band = band_tuple(value, "patterns.$name.$key", source)
        elseif key == "guard"
            guard = config_bool(value, "patterns.$name.$key", source)
        else
            @warn "Dendro: unknown pattern key in $source, ignored" pattern = name key
        end
    end
    isempty(message) && config_error("pattern `$name` in $source needs a `message`")
    validate_pattern_band(name, kind, band, source)
    acc.patterns[Symbol(name)] = PatternSpec(Symbol(name), message, severity, kind, band, guard)
    return nothing
end

# A flag scores nothing, so a band on one is a declaration the author misunderstood. A
# scalar without a band has no absolute score at all. A scalar band starting below 1 lets
# `severity(0, band)` return something other than `:ok`, which would report every unit in
# the corpus for holding no matches.
function validate_pattern_band(name::String, kind::Symbol, band::Union{Nothing, Tuple{Int, Int}}, source)
    if kind === :flag
        band === nothing || config_error("pattern `$name` in $source is a flag and cannot carry a `band`")
    else
        band === nothing && config_error("pattern `$name` in $source is a scalar and needs a `band`")
        first(band) >= 1 ||
            config_error("band for pattern `$name` in $source must start at 1 or higher, got $(first(band))")
    end
    return nothing
end

# `apply_patterns!`, the `[patterns]` table walk, lives in `config.jl` beside the
# `[languages]` one: the two differ only in the key prefix and the per-entry applier, so
# they share `apply_named_tables!`. What is pattern-specific is `apply_pattern!` above.

# --- Where the queries live ---------------------------------------------------------
#
# Two locations, both read and composed: a repo's own rules and the house rules a
# developer shares across repositories. Separate from `[languages].queries`, which
# replaces a whole language profile, so adding one lint rule cannot cost a language its
# scopes query and every binding-based flag.

# The repo-relative default, under the directory holding `.dendro.toml`.
const DEFAULT_PATTERNS_DIR = joinpath(".dendro", "patterns")

"""
    pattern_dirs(config, roots) -> Vector{String}

The directories holding `<lang>.patterns.scm`, in cascade order: the user-global one
first, then the repo's, so a rule defined in both resolves to the repo's.

A `patterns_dir` set in a config file is resolved against that file's own directory, not
the process working directory, so running `dendro` from a subdirectory keeps working.
"""
function pattern_dirs(config::Config, roots)::Vector{String}
    dirs = String[]
    global_dir = joinpath(dirname(global_config_path()), "patterns")
    isdir(global_dir) && push!(dirs, global_dir)
    repo = isempty(config.patterns_dir) ? repo_pattern_dir(roots) : config.patterns_dir
    repo !== nothing && isdir(repo) && push!(dirs, repo)
    return dirs
end

# The repo's own pattern directory: `.dendro/patterns` under the directory a
# `.dendro.toml` would be discovered in. `nothing` when there is no such directory to
# anchor against.
function repo_pattern_dir(roots)
    dir = repo_config_dir(roots)
    return dir === nothing ? nothing : joinpath(dir, DEFAULT_PATTERNS_DIR)
end

# --- Compiling a rule query ---------------------------------------------------------
#
# Tree-sitter checks a query's node types, field names, and capture references when it
# compiles, so a query naming a shape the grammar does not have fails here rather than
# reporting nothing at review time. That checking is the reason rules are queries and not
# Julia functions: a Julia rule matching on node-type strings is checked by nothing.
#
# The one gap is predicates. TreeSitter.jl warns on an unknown one and then rejects every
# match, so a rule using `#same-line?` reads as clean code. `PATTERN_PREDICATES` closes
# it at load.

# The predicates TreeSitter.jl implements, read off its `predicate` dispatch. A query
# naming anything else compiles and then silently rejects every match, so it is rejected
# here instead. The tree predicates read the nodes a capture bound rather than their text,
# which is what puts ancestry, descent, and subtree comparison inside a query at all.
const PATTERN_PREDICATES = Set{String}(
    [
        "eq?", "not-eq?", "any-of?", "not-any-of?", "is?", "is-not?", "match?",
        "not-match?", "any-eq?", "any-not-eq?", "any-match?", "any-not-match?", "set!",
        "has-ancestor?", "not-has-ancestor?", "nearest-ancestor?", "ancestor-match?",
        "not-ancestor-match?", "has-descendant?", "not-has-descendant?", "structure-eq?",
        "not-structure-eq?",
    ]
)

# A predicate call in query text: `(#name? ...`. Predicate names are syntactically
# distinctive, and the C API does not expose them by name before a match is evaluated, so
# reading them off the source is the only way to check one at load.
const PREDICATE_RE = r"\(\s*#([\w!?.-]+)"

"""
    pattern_query_source(dir, language) -> Union{String, Nothing}

The text of `dir/<language>.patterns.scm`, or `nothing` when the file is absent. A
language with no file for a rule simply never fires it, which is not an error: a rule is
declared once and realised per grammar, and no project writes every grammar.
"""
function pattern_query_source(dir::AbstractString, language::Symbol)
    path = joinpath(dir, "$(language).patterns.scm")
    return isfile(path) ? read(path, String) : nothing
end

# 1-based line holding byte offset `offset` in `text`, for turning a `QueryException`'s
# index into something a rule author can navigate to.
line_at_offset(text::String, offset::Int) =
    count(==('\n'), SubString(text, 1, min(max(offset, 0), ncodeunits(text)))) + 1

# The byte offset a `QueryException` names. Its message is
# `"'<kind>' error starting at index <n>"` and it carries nothing else, so the offset is
# recovered from the text rather than from a field.
function query_error_offset(e::TreeSitter.QueryException)
    m = match(r"at index (\d+)", e.msg)
    m === nothing && return 0
    digits = capture_text(m, 1)
    return digits === nothing ? 0 : parse(Int, digits)
end

# The error kind a `QueryException` names: `node type`, `field`, `capture`, `syntax`.
function query_error_kind(e::TreeSitter.QueryException)
    m = match(r"'([^']+)'", e.msg)
    m === nothing && return "query"
    return something(capture_text(m, 1), "query")
end

"""
    compile_pattern_query(grammar, source, path) -> TreeSitter.Query

Compile one `<lang>.patterns.scm`, reporting a malformed query as a [`ConfigError`](@ref)
naming the file and the line rather than a `QueryException` carrying a byte offset.

Fragments are expanded first, and an error inside one names the fragment, where it was
defined, and where it was used, rather than an offset into text the author never wrote.

Predicates are checked against [`PATTERN_PREDICATES`](@ref): an unimplemented one compiles
cleanly and then rejects every match, so a rule using one would report nothing and read as
clean code.
"""
function compile_pattern_query(
        grammar, source::AbstractString, path::AbstractString; specs::Vector{PatternSpec} = PatternSpec[]
    )
    fragments = collect_fragments(source, path)
    check_fragment_names(fragments, specs, path)
    expanded = expand_fragments(source, path)
    check_predicates(expanded.text, path)
    try
        return TreeSitter.Query(grammar, expanded.text)
    catch e
        e isa TreeSitter.QueryException || rethrow()
        # Resolved through the expansion map, so an error inside a spliced fragment names
        # the fragment rather than an offset into text the author never wrote.
        config_error("$(query_error_kind(e)) error at $(error_site(expanded, query_error_offset(e), path))")
    end
end

# Reject a predicate TreeSitter.jl does not implement, naming the alternatives, since a
# reader hitting this needs to know what to use instead.
function check_predicates(source::String, path::AbstractString)
    for m in eachmatch(PREDICATE_RE, source)
        name = capture_text(m, 1)
        (name === nothing || name in PATTERN_PREDICATES) && continue
        line = line_at_offset(source, m.offset - 1)
        available = join(sort!(collect(PATTERN_PREDICATES)), ", ")
        config_error(
            "unknown predicate `#$name` at line $line of $path. Available: $available"
        )
    end
    return nothing
end

# --- Bucketing a rule's matches -----------------------------------------------------
#
# A pattern query's captures name rules, so the walk buckets by name rather than routing
# through `dispatch!`. Three conventions the capture name carries:
#
#   @rule       a match to report
#   @rule.not   a match to subtract from `@rule`, by node identity
#   @_anything  a helper the query needed so a predicate had something to reference
#
# The helper convention is not cosmetic. A predicate must name a capture, so `#eq? @_n
# "print"` forces capturing the identifier it tests; without the `_` prefix that capture
# would become a rule of its own and fire on every node the predicate examined. Measured
# across 44 rules in 12 languages, 23 carried at least one helper.

# The suffix marking a capture as subtracting from the rule of the same name.
const PATTERN_NOT_SUFFIX = ".not"

# The prefix marking a capture as a predicate helper rather than a rule.
const PATTERN_HELPER_PREFIX = '_'

# True when a capture name is a helper for a predicate rather than a rule to report.
is_helper_capture(name::String) =
    !isempty(name) && first(name) == PATTERN_HELPER_PREFIX

# The rule a capture name belongs to, and whether it subtracts. A `.not` suffix is
# stripped; anything else is the rule name itself.
function capture_rule(name::String)
    endswith(name, PATTERN_NOT_SUFFIX) &&
        return Symbol(SubString(name, 1, lastindex(name) - length(PATTERN_NOT_SUFFIX))), true
    return Symbol(name), false
end

"""
    declared_captures(query) -> Vector{String}

Every capture name `query` declares, whether or not it matched anything. Read off the
compiled query rather than off a walk, so a rule that matches nothing in a given file is
still known to have been declared: that is what lets a repo rule shadow a user-global one
of the same name even where it happens not to fire.
"""
function declared_captures(query::TreeSitter.Query)
    n = TreeSitter.capture_count(query)
    len = Ref{UInt32}()
    return String[
        unsafe_string(TreeSitter.API.ts_query_capture_name_for_id(query.ptr, UInt32(i), len))
            for i in 0:(n - 1)
    ]
end

"""
    check_declared_rules(query, specs, path)

Reject a capture naming a rule no `[patterns.<name>]` table declares.

Declaration is required rather than inferred, because inferring it turns two ordinary
mistakes into silent misbehaviour: a typo'd `@no_anyy` becomes a rule reporting under a
name nobody wrote, and a helper capture that lost its `_` becomes a rule firing on every
node its predicate examined. Checked once per compiled query at load, never per file.
"""
function check_declared_rules(query::TreeSitter.Query, specs::Vector{PatternSpec}, path::AbstractString)
    known = Set(s.name for s in specs)
    for name in declared_captures(query)
        is_helper_capture(name) && continue
        rule, _ = capture_rule(name)
        rule in known && continue
        config_error(
            "capture `@$name` in $path names no declared rule. Add a `[patterns.$rule]` " *
                "table, or prefix the capture with `_` if it is a predicate helper"
        )
    end
    return nothing
end

"""
    index_patterns!(index, tree, query, source)

Walk `query` over `tree` and bucket every capture into `index.patterns` by rule name.

Several patterns may share one capture name and accumulate into one bucket, which is what
lets a rule carry more than one shape: a `console.*` call and a `debugger` statement both
capturing `@debug_output` are one rule with two spellings.

`skip` names rules a higher-priority location already declares, whose captures here are
dropped rather than merged.
"""
function index_patterns!(
        index::QueryIndex, tree::TreeSitter.Tree, query::TreeSitter.Query, source::AbstractString;
        skip::Set{Symbol} = Set{Symbol}()
    )
    for cap in TreeSitter.each_capture(tree, query, source)
        name = TreeSitter.capture_name(query, cap)
        is_helper_capture(name) && continue
        rule, negated = capture_rule(name)
        rule in skip && continue
        bucket = get!(PatternBucket, index.patterns, rule)
        record!(negated ? bucket.excluded : bucket.hits, cap.node)
    end
    return index
end

"""
    pattern_hits(index, name) -> Vector{TreeSitter.Node}

The nodes rule `name` reports in this tree: what its query captured, less what its `.not`
patterns cancelled. Empty when the rule has no query for this language, which is ordinary
rather than an error.
"""
function pattern_hits(index::QueryIndex, name::Symbol)::Vector{TreeSitter.Node}
    bucket = get(index.patterns, name, nothing)
    bucket === nothing && return TreeSitter.Node[]
    return TreeSitter.Node[n for n in bucket.hits.nodes if !(n in bucket.excluded)]
end

# --- Resolving a language's rules across both locations -------------------------------
#
# Both pattern directories are read and composed, so house rules kept in
# `~/.config/dendro/patterns/` survive a repo adding its own. When both define the same
# rule for the same language, the repo's wins for that pair.
#
# Shadowing is by *declared* capture, not by matched one. A repo rule that happens to
# match nothing in a given file must still shadow the user-global rule of the same name
# there, or the global one would leak back in exactly where the repo's found nothing.

"""
    PatternQuery

One compiled `<lang>.patterns.scm` and the rules a higher-priority location already
declares, which this query's captures are skipped for.
"""
struct PatternQuery
    query::TreeSitter.Query
    shadowed::Set{Symbol}
end

# Compiled pattern queries per language, keyed so two scans of the same project share the
# work. A `Query` wraps a C pointer that cannot survive precompilation, so this fills
# lazily at runtime like `QUERY_CACHE` does.
const PATTERN_QUERY_CACHE = Dict{Tuple{Symbol, Vector{String}, Vector{Symbol}}, Vector{PatternQuery}}()

"""
    pattern_queries(profile, dirs, specs) -> Vector{PatternQuery}

Every compiled pattern query for one language, lowest priority first, each carrying the
rules a later location shadows. Empty when no location holds a file for the language.

Each query is validated as it compiles: node types by tree-sitter, predicates by
[`PATTERN_PREDICATES`](@ref), and capture names against `specs`.
"""
function pattern_queries(profile::LanguageProfile, dirs::Vector{String}, specs::Vector{PatternSpec})
    key = (profile.name, dirs, Symbol[s.name for s in specs])
    return lock(CACHE_LOCK) do
        get!(PATTERN_QUERY_CACHE, key) do
            build_pattern_queries(profile, dirs, specs)
        end
    end
end

function build_pattern_queries(profile::LanguageProfile, dirs::Vector{String}, specs::Vector{PatternSpec})
    grammar = language_grammar(profile)
    found = Tuple{TreeSitter.Query, Set{Symbol}}[]
    for dir in dirs
        source = pattern_query_source(dir, profile.name)
        source === nothing && continue
        path = joinpath(dir, "$(profile.name).patterns.scm")
        query = compile_pattern_query(grammar, source, path; specs)
        check_declared_rules(query, specs, path)
        push!(found, (query, rules_declared_by(query)))
    end
    # Walk backwards accumulating what the higher-priority locations claim, so each entry
    # learns which of its own rules a later one has already answered for.
    out = Vector{PatternQuery}(undef, length(found))
    claimed = Set{Symbol}()
    for i in reverse(eachindex(found))
        query, declares = found[i]
        out[i] = PatternQuery(query, copy(claimed))
        union!(claimed, declares)
    end
    return out
end

# The rule names a compiled query declares, helpers and `.not` suffixes folded away.
function rules_declared_by(query::TreeSitter.Query)
    out = Set{Symbol}()
    for name in declared_captures(query)
        is_helper_capture(name) && continue
        push!(out, first(capture_rule(name)))
    end
    return out
end

"""
    index_all_patterns!(index, tree, queries, source)

Bucket every location's pattern query into `index`, skipping the rules a
higher-priority location has already declared.
"""
function index_all_patterns!(
        index::QueryIndex, tree::TreeSitter.Tree, queries::Vector{PatternQuery}, source::AbstractString
    )
    for pq in queries
        # Seed a bucket for every rule this query declares, so a rule that has a query here
        # but matches nothing is still distinguishable from one with no query at all. That
        # is what `unmatched_patterns` reads to tell a broken rule from a silent one.
        for rule in rules_declared_by(pq.query)
            rule in pq.shadowed || get!(PatternBucket, index.patterns, rule)
        end
        index_patterns!(index, tree, pq.query, source; skip = pq.shadowed)
    end
    return index
end

# --- From a declaration to a rule -----------------------------------------------------
#
# Once a spec and its query exist, a pattern rule is an ordinary `Rule`. That is the whole
# point: suppression, diff scoping, the report, the gate, and the ratchet then work with
# no further code, and a house rule sits beside `cyclomatic` under one vocabulary.

# Count a rule's hits within one unit, stopping at nested callables so a closure's matches
# do not land on the enclosing function. Every built-in scalar stops there, and a pattern
# scalar that did not would read as a Dendro bug.
#
# The bucket travels as `fold_unit`'s context rather than being captured, so the step stays
# a plain function and the accumulator stays concretely typed for inference and JET. See
# the note on `fold_unit` in `metrics.jl`. The index goes unread here, unlike every
# concept-reading step, since the rule's matches are already bucketed by name.
pattern_step(node::TreeSitter.Node, _index::QueryIndex, bucket::PatternBucket) =
    count_if(node in bucket.hits && !(node in bucket.excluded), bucket)

"""
    pattern_count(unit, index, name) -> Int

How many times rule `name` matched inside `unit`, excluding nested callables. Zero when
the rule has no query for this language.
"""
function pattern_count(unit::FunctionUnit, index::QueryIndex, name::Symbol)
    bucket = get(index.patterns, name, nothing)
    bucket === nothing && return 0
    return fold_unit(pattern_step, +, unit.node, index, bucket)
end

"""
    pattern_rule(spec) -> Rule

The [`Rule`](@ref) one [`PatternSpec`](@ref) declares. A flag reports each matched node at
the spec's severity; a scalar counts its matches per unit and is scored against the spec's
band and the corpus percentile, exactly as a built-in scalar is.
"""
function pattern_rule(spec::PatternSpec)
    spec.kind === :scalar &&
        return Rule(spec.name, :scalar, spec.band, (u, i) -> pattern_count(u, i, spec.name), spec.severity)
    return Rule(spec.name, :flag, nothing, i -> pattern_hits(i, spec.name), spec.severity)
end

# --- Rules that matched nothing -------------------------------------------------------

"""
    unmatched_patterns(files, specs) -> Vector{Symbol}

The declared rules that matched nothing anywhere in `files`, sorted by name.

A rule whose query compiles and then matches nothing reads as clean code. Tree-sitter
catches a query naming a node type the grammar lacks, and the predicate allowlist catches
an unimplemented predicate, but neither catches a well-formed query naming a shape that
simply never occurs. This does.

A rule is only reported when the corpus actually holds a file of a language it has a query
for: a Python-only rule scanned over a Julia repo has not failed, it just had nothing to
say.

A rule declaring `guard = true` is never reported. The two silences are different things: a
rule naming a shape the grammar never produces is broken, and a rule catching what a project
has decided never to write is working. Nothing in the query tells them apart, so the
declaration does.
"""
function unmatched_patterns(files::Vector{ParsedFile}, specs::Vector{PatternSpec})
    isempty(specs) && return Symbol[]
    matched = Set{Symbol}()
    for f in files, (name, bucket) in f.index.patterns
        isempty(bucket.hits.nodes) || push!(matched, name)
    end
    reachable = reachable_pattern_rules(files)
    return sort!(
        Symbol[
            s.name for s in specs
                if !s.guard && s.name in reachable && !(s.name in matched)
        ]
    )
end

# The rules that had a query to run against at least one file in the corpus. A rule with no
# query for any language present is silent by construction, not broken.
function reachable_pattern_rules(files::Vector{ParsedFile})
    out = Set{Symbol}()
    for f in files
        union!(out, keys(f.index.patterns))
    end
    return out
end
