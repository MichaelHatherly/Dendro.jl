# Public definitions carrying no documentation. A declared-public top-level definition with
# no doc node against it is reported as `:undocumented_public`: a caller outside the corpus
# can reach the name and has nothing to read about what it does. The cross-file companion to
# `:unreferenced`, reading the public surface that pass roots its search from, less the
# `:package` names: a package-private Java method or a Rust `pub(crate)` item is alive to
# reachability and owes a caller outside the package nothing, so `def_api` leaves it out.
#
# Documentation is read as adjacency and never as content. Nothing syntactic separates a
# docstring that states a contract from one restating the name above it, so the honest
# question is whether a definition has one at all. The `@doc` capture names the node each
# language's own readers and doc tools take as documentation, which is why Go tags every `//`
# line where Rust tags only `///`. The tool is the standard for what else counts. A doc
# comment reaches its definition across a plain comment, as rustdoc, javadoc and tsc read it.
# An overriding method inherits the overridden one's documentation, which javadoc copies
# onto an `@Override` method and rustdoc shows on every method of a trait impl, so a
# definition inside an `@inherits_doc` node is documented. A constructor is documented by
# its class, which is where RDoc and javadoc present it, so a bare `initialize` under an
# undocumented class adds nothing to the finding the class already carries. A docstring
# documents a name where a doc comment documents a form: Julia's doc system shows one
# docstring on every method of a generic, and Sphinx documents a function once whatever its
# `typing.overload` stubs, where javadoc is written per overload. So a definition is
# documented when a same-name definition in its file carries a docstring, never a doc
# comment, and never across files. C and C++
# declare a name apart from defining it, and curl documents at the prototype in the header,
# so a definition is documented when a same-name `@prototype` anywhere in the corpus is. The
# header is also what makes the definition API: a non-`static` function no header declares
# is file-local in practice whatever its linkage, so `HEADER_LANGUAGES` narrows `def_api` to
# a definition in a header or named by a prototype in one. An RDoc `:nodoc:` on a
# definition's line, or `:nodoc: all` on the line of a class around it, is the author
# declaring the name out of the documented surface, so a `@nodoc` marker drops the finding.
#
# A language with no `LINKAGES` entry reads as private and is passed over, the inverse of
# `:unreferenced`'s default. There an unknown visibility read as private would hide dead
# code; here it would put a finding on every definition of a language whose public surface
# Dendro cannot read, so silence is the safe failure.
#
# Zero overlap with `comment_density` by construction. A docstring is a string and never a
# `@comment`, and a doc comment documents the definition below it, where the per-unit fold
# never reaches. A comment inside a body is the other way round: it raises `comment_density`
# and documents nothing here. So a project documenting entirely in docstrings scores
# `comment_density` 0 and `:undocumented_public` 0 at once.
#
# Off by default, and the measurement says why. Over fourteen corpora in ten languages the
# undocumented share of the public surface runs from 6.7% (ripgrep) to 93.8% (curl), five of
# them above half. That spread is not a quality ordering. It is what each community documents
# and where: curl documents in its headers and its manual, guava inherits a javadoc on every
# overriding method, Julia attaches one docstring to a generic whose other methods then read
# bare. A rule reporting on half a corpus at once is a standard a project opts into, not a
# default, so this ships behind `[rules] undocumented_public = true` at `:warn` and never
# reaches the `errors` floor.

# The definition kinds the rule asks after, and the measurement is what leaves constants out.
# Of CommonMark.jl's 58 findings 42 are one vendored table of colour constants, and every one
# of go-sdk's 13 is a `const (...)` block carrying a single comment above the group. Both are
# the norm rather than the exception: a language documents a constant table once at the table,
# so asking after each entry reports one observation dozens of times. A function, type or
# macro is a contract a caller reads on its own, which is what makes asking after each one
# worth a finding.
const DOCUMENTED_KINDS = (:function, :struct, :class, :macro)

# The 1-based line a node's text last occupies. A line comment's span can run to the start
# of the following line, where it carried no text, so a span ending in column 0 last covered
# the line above.
function last_text_line(n::TreeSitter.Node)
    p = TreeSitter.end_point(n)
    return Int(p.row) + (p.column == 0 ? 0 : 1)
end

# One node as the shape the documentation test reads a construct in: byte range and first
# line.
function node_span(n::TreeSitter.Node)
    from, to = TreeSitter.byte_range(n)
    return (from, to, line_of(n))
end

# The index of the tightest of `spans` covering `[from, to]`, or 0 when none does. A doc node
# documents the tightest construct it sits inside, so a method's docstring never answers for
# the class around it.
function tightest_span(spans::Vector{Tuple{Int, Int, Int}}, from::Int, to::Int)
    best, width = 0, 0
    for (i, s) in enumerate(spans)
        (s[1] <= from && to <= s[2]) || continue
        (best == 0 || s[2] - s[1] < width) && (best = i; width = s[2] - s[1])
    end
    return best
end

# The construct one definition's documentation attaches to: the callable unit holding its
# name, the class declaring it, or the name itself for a definition that is neither. A
# docstring sits inside that span and a doc comment on the line above its first, which is why
# the span is what the test reads rather than the name's own line: Java writes an annotation
# between the two, inside the declaration.
function documented_span(units::Vector{Unit}, classes::Vector{Tuple{Int, Int, Int}}, d::CorpusDef)
    if d.unit != 0
        u = units[d.unit]
        from, to = unit_span(u)
        return (from, to, u.firstline)
    end
    i = tightest_span(classes, d.id[1], d.id[2])
    return i == 0 ? (d.id[1], d.id[2], d.line) : classes[i]
end

# Every line a doc comment reaches its definition across: an attribute, which Rust writes
# between the two as a sibling of both, and a plain comment, which rustdoc, javadoc and tsc
# all read past. A doc node is never one, so a run of doc comments still lands on its last
# line, and a docstring steps over nothing: Julia's parser pairs it with the form directly
# below and a comment between the two leaves the string unpaired.
function stepped_lines(index::QueryIndex)
    lines = Set{Int}()
    for n in Iterators.flatten((index.attribute.nodes, index.comment.nodes))
        n in index.doc && continue
        union!(lines, line_of(n):last_text_line(n))
    end
    return lines
end

# Every construct in one file a doc node can attach to: the definitions asked about, plus the
# callable units and classes around them. The wider set is what keeps a method's docstring on
# the method where the symbol table holds only the class, as Python's does. Without it one
# documented member would answer for the container.
function doc_candidates(index::QueryIndex, classes::Vector{Tuple{Int, Int, Int}}, spans::Vector{Tuple{Int, Int, Int}})
    candidates = copy(spans)
    for u in index.units
        from, to = unit_span(u)
        push!(candidates, (from, to, u.firstline))
    end
    return append!(candidates, classes)
end

# The byte ranges among `candidates` one doc node documents: the construct whose first line
# follows it, the preceding form, and for a docstring also the construct it sits inside.
# Containment is the docstring form's alone: a doc node that is also a `@comment` can sit
# anywhere in a body, where a docstring is the body's first statement and the query already
# anchors it there. A multi-line run of `//` or `#` lines is one node per line, and only the
# last lands against the definition, which is what makes a run count once.
function doc_targets(index::QueryIndex, candidates::Vector{Tuple{Int, Int, Int}}, stepped::Set{Int}, doc::TreeSitter.Node)
    hits = Tuple{Int, Int}[]
    from, to = TreeSitter.byte_range(doc)
    inner = doc in index.comment ? 0 : tightest_span(candidates, from, to)
    inner == 0 || push!(hits, (candidates[inner][1], candidates[inner][2]))
    target = last_text_line(doc) + 1
    while doc in index.comment && target in stepped
        target += 1
    end
    for c in candidates
        c[3] == target && push!(hits, (c[1], c[2]))
    end
    return hits
end

# Which of `spans` carry documentation, and which of those carry it as a docstring, each
# aligned with `spans`. The second is what lets a docstring document a name across the file
# where a doc comment documents one form, so the caller can share it between same-name
# definitions without a javadoc on one overload answering for another.
#
# Two constructs read as documented with no doc node of their own. A definition inside an
# `@inherits_doc` node overrides something whose documentation its doc tool shows in place of
# the missing one. A `@constructor` inside a class is documented by the class, whose docs say
# how to build one, so the class carries the finding when those are missing and the
# constructor never does.
function documented_spans(index::QueryIndex, classes::Vector{Tuple{Int, Int, Int}}, spans::Vector{Tuple{Int, Int, Int}})
    candidates = doc_candidates(index, classes, spans)
    stepped = stepped_lines(index)
    documented = Set{Tuple{Int, Int}}()
    by_docstring = Set{Tuple{Int, Int}}()
    for doc in index.doc.nodes
        hits = doc_targets(index, candidates, stepped, doc)
        union!(documented, hits)
        doc in index.comment || union!(by_docstring, hits)
    end
    for m in index.inherits_doc.nodes
        from, to = TreeSitter.byte_range(m)
        for c in candidates
            from <= c[1] && c[2] <= to && push!(documented, (c[1], c[2]))
        end
    end
    for ctor in index.constructor.nodes
        from, to = TreeSitter.byte_range(ctor)
        tightest_span(classes, from, to) == 0 || push!(documented, (from, to))
    end
    flags = falses(length(spans))
    docstrings = falses(length(spans))
    for (i, s) in enumerate(spans)
        flags[i] = (s[1], s[2]) in documented
        docstrings[i] = (s[1], s[2]) in by_docstring
    end
    return flags, docstrings
end

# The byte and line spans of one file's classes, the containers a definition's documentation
# may attach to instead of the definition.
class_spans(index::QueryIndex) = Tuple{Int, Int, Int}[node_span(c) for c in index.class.nodes]

# What the corpus's prototypes say about the names they declare: which some documented
# prototype names, and which a header declares. Both are corpus-wide facts, since the
# prototype and the definition sit in different files, and a definition in a
# `HEADER_LANGUAGES` file is judged by them: documented when a prototype of its name is, and
# API only when a header names it.
function prototype_facts(files::Vector{ParsedFile})
    documented = Set{String}()
    declared = Set{String}()
    for parsed in files
        protos = parsed.index.prototype.nodes
        isempty(protos) && continue
        spans = Tuple{Int, Int, Int}[node_span(p) for p in protos]
        flags, _ = documented_spans(parsed.index, class_spans(parsed.index), spans)
        header = is_header(parsed.file)
        for (p, documented_here) in zip(protos, flags)
            name = unit_name(p, parsed.index)
            documented_here && push!(documented, name)
            header && push!(declared, name)
        end
    end
    return (documented = documented, declared = declared)
end

# The lines a `@nodoc` marker sits on, each mapped to whether it is the `all` form, which
# covers a class's members along with the class.
function nodoc_lines(index::QueryIndex)
    lines = Dict{Int, Bool}()
    for n in index.nodoc.nodes
        lines[line_of(n)] = occursin(r":nodoc:\s+all\b", TreeSitter.slice(index.source, n))
    end
    return lines
end

# Whether the author declared a definition out of the documented surface: a marker on the
# line its documentation would attach to, or the `all` form on the line of a class around
# it. The class's own span is among `classes`, so `all` covers the class too.
function nodoc_excluded(lines::Dict{Int, Bool}, span::Tuple{Int, Int, Int}, classes::Vector{Tuple{Int, Int, Int}})
    isempty(lines) && return false
    haskey(lines, span[3]) && return true
    return any(c -> c[1] <= span[1] && span[2] <= c[2] && get(lines, c[3], false), classes)
end

# Whether a definition in a language with headers is one a header declares: it sits in a
# header, or a prototype in one names it. A non-`static` function no header declares is
# file-local in practice whatever its linkage, so nobody outside has it to read about.
header_declared(d::CorpusDef, declared::Set{String}) = is_header(d.file) || d.name in declared

"""
    cluster_undocumented_public(files, table, linkage=resolve_linkage(files, table)) -> Vector{Finding}

Declared-public top-level definitions with no documentation against them, reported as
`:undocumented_public`, one finding per definition at `:warn`. Functions, types and macros
are asked after; a constant is not, since a language documents a table of constants once at
the table. Publicness is the surface [`reach_graph`](@ref) roots its search from, narrowed
twice. A `:package` definition (a Java method with no modifier, a Rust `pub(crate)` item) is
reachable within its package and outside the API, so it is left out. And a language with no
`LINKAGES` entry reads as private here where it reads public there, so the rule stays silent
on a corpus whose public surface Dendro cannot read.

Documentation is adjacency, never content: a definition is documented when a `@doc` node sits
on the line above it, a doc comment stepping over any attribute and plain comment lines
between, or, for a docstring, inside it. What the node says is never read, so a docstring
stating a contract and one restating the name above it count alike. A definition inside an
`@inherits_doc` node (a Java `@Override` method, a Rust trait impl) inherits the overridden
one's documentation, and a `@constructor` inside a class is documented by the class, so
neither is reported. A docstring documents a name, so a definition whose same-name sibling
in the file carries one (the other methods of a Julia generic) is documented too; a doc
comment documents one form and shares nothing, since javadoc is written per overload. In a
language with headers (C, C++) a definition is also documented
when a `@prototype` of its name anywhere in the corpus is, and it is API only when it sits
in a header or a header declares it, since a function no header declares is file-local in
practice whatever its linkage. A definition under a `@nodoc` marker (RDoc's `:nodoc:` on
its line, or `:nodoc: all` on its class's) is declared out of the documented surface and
never reported. Suppressed when its line carries a
`dendro-ignore: undocumented_public` directive.

This shares no ground with `comment_density`, and the reason is structural. A doc node is
either a string, which is not a `@comment`, or a sibling outside the definition span, which
the per-unit fold never reaches.

Pass a prebuilt `linkage` from [`resolve_linkage`](@ref) to share one resolution with a
caller that has already resolved the corpus. It is positional where the sibling passes take
it by keyword, and that is measured: a keyword splits a method into a `kwcall` wrapper and a
body, and the sound analyser then raises three more reports against the body, the same
trade `cluster_class_size` makes for its `band`.
"""
function cluster_undocumented_public(
        files::Vector{ParsedFile}, table::SymbolTable,
        linkage::ResolvedLinkage = resolve_linkage(files, table)
    )
    findings = Finding[]
    bypath = Dict{String, Vector{Int}}()
    for (i, d) in enumerate(table.defs)
        push!(get!(() -> Int[], bypath, d.file), i)
    end
    protos = prototype_facts(files)
    for parsed in files
        ids = get(bypath, parsed.file, nothing)
        ids === nothing && continue
        link = get(LINKAGES, parsed.language, nothing)
        link === nothing && continue
        headered = parsed.language in HEADER_LANGUAGES
        classes = class_spans(parsed.index)
        spans = Tuple{Int, Int, Int}[documented_span(parsed.index.units, classes, table.defs[i]) for i in ids]
        documented, by_docstring = documented_spans(parsed.index, classes, spans)
        docstring_names = Set{String}(table.defs[i].name for (k, i) in enumerate(ids) if by_docstring[k])
        nodoc = nodoc_lines(parsed.index)
        for (k, i) in enumerate(ids)
            documented[k] && continue
            nodoc_excluded(nodoc, spans[k], classes) && continue
            d = table.defs[i]
            d.name in docstring_names && continue
            headered && d.name in protos.documented && continue
            d.kind in DOCUMENTED_KINDS || continue
            def_api(link, d, linkage.surface) || continue
            headered && !header_declared(d, protos.declared) && continue
            sup = is_suppressed(parsed.directives, d.line, RELATIONAL.undocumented_public)
            push!(
                findings,
                Finding(
                    RELATIONAL.undocumented_public, [Location(d.file, d.line, d.name)],
                    nothing, :warn, nothing, :flag, sup
                )
            )
        end
    end
    sort!(findings; by = f -> (first(f.locations).file, first(f.locations).line))
    return findings
end
