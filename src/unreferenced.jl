# Dead private code by reachability. A top-level definition no path reaches from the
# corpus's public surface is unreferenced: nothing outside the corpus can name it and
# nothing inside does. The cross-file companion to `:misplaced` and `:scattered`, reading
# the same name-based, lexical resolution: a reference resolves to the definition it names
# along declared visibility, never by type or dispatch.
#
# Dead code needs reachability, not in-degree zero: a private cluster that only calls
# itself is dead even though each member is referenced. So the pass builds a reference
# graph over `table.defs` and walks forward from the roots. A def is a root when it is
# declared public (the language's public surface) or referenced from top-level code,
# which runs unconditionally. Edges come from two sources, neither discounted: within-file
# bindings (`f.index.bindings`) and cross-file references resolved through visibility. A
# ubiquitous definition is maximally alive, so unlike the corpus graph this drops no
# cross-cutting utility and keeps non-unit targets.
#
# The model is sound only over a whole module: a private def called from a same-module
# file outside the scan is falsely flagged. Runtime-only entry points (a test function, a
# dispatch-table callback, a string-dispatched name) are flagged too, since no syntactic
# reference reaches them; accept one with `dendro-ignore: unreferenced`. `external_root`
# roots a hook the language runtime calls by name, Julia's `__init__`, and a definition a
# decorator, annotation, or attribute registers. A method a base class plausibly calls, an
# override, roots too (`plausible_overrides`).

# The methods a base class plausibly calls: each function inside a class that extends
# another, when that base is defined nowhere in the corpus (its methods are unknown, so
# any could be overridden) or when the base defines a function of the same name. Name-based
# and lexical, like the rest of the pass: a base matches a corpus type by name, never by
# resolving which one it is, and a base outside the corpus reads as overridable.
function plausible_overrides(table::SymbolTable)
    types = Set{String}(d.name for d in table.defs if is_type_kind(d.kind))
    members = Set{Tuple{String, String}}(
        (last(d.module_path), d.name) for d in table.defs if d.kind === :function && !isempty(d.module_path)
    )
    return Set{Int}(
        i for (i, d) in enumerate(table.defs)
            if d.kind === :function && !isempty(d.base) && (!(d.base in types) || (d.base, d.name) in members)
    )
end

# The graph node for a reference's source: the top-level definition whose function body
# contains it by byte range, or 0 (ROOT) for a reference in top-level code. Attribution is
# by containment, not the innermost unit: a reference inside a nested helper or a lambda
# belongs to the enclosing top-level def, whose edge would otherwise be lost. Top-level
# function bodies are pairwise byte-disjoint, so at most one contains a position.
function enclosing_def(ranges::Vector{Tuple{Int, Int, Int}}, from::Int, to::Int)
    for (rf, rt, di) in ranges
        rf <= from && to <= rt && return di
    end
    return 0
end

"""
    reach_graph(files, table; linkage=resolve_linkage(files, table), entry_points=String[]) -> (adj, roots)

The forward reference graph over `table.defs` and the root set a dead-code search starts
from. `adj[i]` lists the definition indices definition `i` references; `roots` holds the
declared-public definitions, those referenced from top-level code, the external roots a
runtime hook or a registering wrapper reaches, the `plausible_overrides`, and every
definition named in `entry_points`, an entry point called from outside the scanned roots.
Edges come from within-file bindings and cross-file references, each attributed to its
enclosing top-level definition by byte range; a reference in top-level code seeds a root
rather than an edge.

The cross-file edges and the public surface both come out of `linkage`, so a scan that has
already resolved the corpus does not resolve it again here.
"""
function reach_graph(
        files::Vector{ParsedFile}, table::SymbolTable;
        linkage::ResolvedLinkage = resolve_linkage(files, table),
        entry_points::Vector{String} = String[]
    )
    n = length(table.defs)
    named = Set(entry_points)
    adj = [Int[] for _ in 1:n]
    roots = Set{Int}()
    file_by_path = Dict{String, ParsedFile}(f.file => f for f in files)
    surface = linkage.surface

    # The top-level function body ranges per file, a definition's index keyed by its
    # name-node identity, and the definitions sharing a file and name, the three lookups
    # the edges resolve against. A def carrying a function unit (`unit != 0`) is a
    # top-level function; one at file scope is a leaf. Same-file same-name definitions
    # resolve together: a reference binds lexically to one, but name resolution cannot
    # tell a type from its constructor or one method from its overload, so reaching one
    # reaches all, the within-file counterpart of the cross-file candidate split.
    topfns = Dict{String, Vector{Tuple{Int, Int, Int}}}()
    byid = Dict{Tuple{String, NodeId}, Int}()
    name_class = Dict{Tuple{String, String}, Vector{Int}}()
    union!(roots, plausible_overrides(table))
    for (i, d) in enumerate(table.defs)
        byid[(d.file, d.id)] = i
        push!(get!(() -> Int[], name_class, (d.file, d.name)), i)
        link = get(LINKAGES, file_by_path[d.file].language, nothing)
        public = link === nothing || link.is_public(d, get(() -> Set{String}(), surface, d.file))::Bool
        (public || d.external_root || d.name in named) && push!(roots, i)
        d.unit == 0 && continue
        from, to = unit_span(file_by_path[d.file].index.units[d.unit])
        push!(get!(() -> Tuple{Int, Int, Int}[], topfns, d.file), (from, to, i))
    end
    # A function's methods can sit in several files of one namespace, so a name class also
    # holds the same-name definitions its file sees across the boundary: the candidates a
    # cross-file reference by that name carries.
    no_candidates = Int[]
    for ((file, name), class) in name_class
        append!(class, get(linkage.visible[file], name, no_candidates))
    end

    empty_ranges = Tuple{Int, Int, Int}[]
    # Within-file edges: each binding's reference attributes to its enclosing top-level
    # def, its targets every same-name definition its file sees when the named one is a
    # top-level symbol.
    for f in files
        ranges = get(topfns, f.file, empty_ranges)
        for (refid, defid) in f.index.bindings
            target = get(byid, (f.file, defid), 0)
            target == 0 && continue
            targets = name_class[(f.file, table.defs[target].name)]
            src = enclosing_def(ranges, refid[1], refid[2])
            src == 0 ? union!(roots, targets) : append!(adj[src], targets)
        end
    end

    # Cross-file edges: each resolved reference attributes to its enclosing top-level def,
    # its targets every candidate definition the name reaches.
    for reference in linkage.references
        ranges = get(topfns, reference.file.file, empty_ranges)
        src = enclosing_def(ranges, reference.ref.id[1], reference.ref.id[2])
        if src == 0
            for target in reference.candidates
                push!(roots, target)
            end
        else
            append!(adj[src], reference.candidates)
        end
    end
    return adj, roots
end

# Mark node `i` seen and enqueue it the first time, the step the breadth-first walk
# repeats from the roots and from each node's neighbours.
function enqueue_unseen!(seen::BitVector, queue::Vector{Int}, i::Int)
    seen[i] && return nothing
    seen[i] = true
    push!(queue, i)
    return nothing
end

# The definitions reachable from `roots` over `adj`, by breadth-first walk. A node is a
# leaf with an empty adjacency, so a type or const reached as a target stays reached.
function reachable(adj::Vector{Vector{Int}}, roots::Set{Int})
    seen = falses(length(adj))
    queue = Int[]
    for r in roots
        enqueue_unseen!(seen, queue, r)
    end
    while !isempty(queue)
        for v in adj[pop!(queue)]
            enqueue_unseen!(seen, queue, v)
        end
    end
    return seen
end

"""
    cluster_unreferenced(files, table; linkage=resolve_linkage(files, table), roots=String[]) -> Vector{Finding}

Top-level definitions no path reaches from the corpus's public surface, reported as
`:unreferenced`, one finding per definition. Reachability follows [`reach_graph`](@ref):
declared-public definitions and those referenced from top-level code are roots, and the
within-file and cross-file reference edges carry liveness from there. An unreached
definition is necessarily private, so no public recheck is needed. Suppressed when its
line carries a `dendro-ignore: unreferenced` directive. Sound only over a whole module: a
definition referenced from a same-module file outside the scan is falsely flagged.

Pass a prebuilt `linkage` from [`resolve_linkage`](@ref) to share one resolution with a
caller that has already resolved the corpus. `roots` names entry points reached from
outside the scan, a loader script or another package, which root reachability by name
like a public definition; `[unreferenced] roots` in a `.dendro.toml` sets them.
"""
function cluster_unreferenced(
        files::Vector{ParsedFile}, table::SymbolTable;
        linkage::ResolvedLinkage = resolve_linkage(files, table),
        roots::Vector{String} = String[]
    )
    findings = Finding[]
    adj, starts = reach_graph(files, table; linkage, entry_points = roots)
    seen = reachable(adj, starts)
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    for (i, d) in enumerate(table.defs)
        seen[i] && continue
        sup = is_suppressed(get(() -> Directive[], directives, d.file), d.line, RELATIONAL.unreferenced)
        push!(findings, Finding(RELATIONAL.unreferenced, [Location(d.file, d.line, d.name)], nothing, :high, nothing, :flag, sup))
    end
    sort!(findings; by = f -> (first(f.locations).file, first(f.locations).line))
    return findings
end
