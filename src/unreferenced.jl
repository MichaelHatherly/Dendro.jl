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
# reference reaches them; accept one with `dendro-ignore: unreferenced`.

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

# Record one reference's targets against `src`, the top-level definition containing it or 0
# for a reference in top-level code. A reference from a definition draws an edge per target;
# one from top-level code names its targets with no definition behind it.
function record_reference!(
        edges::Vector{Tuple{Int, Int}}, toplevel::Vector{Int}, src::Int, targets::Vector{Int}
    )
    if src == 0
        append!(toplevel, targets)
    else
        for target in targets
            push!(edges, (src, target))
        end
    end
    return nothing
end

"""
    reference_edges(files, table, linkage) -> (edges, toplevel)

Every reference between the definitions of `table`, as a `(source, target)` index pair per
reference, and the definitions named from top-level code. A reference is attributed to the
top-level definition whose body contains it by byte range; one no definition contains runs
in top-level code and lands in `toplevel`, carrying no source.

Both edge sets are here, neither discounted for breadth: within-file bindings, whose targets
are every same-file definition sharing the named one's name, and cross-file references,
whose targets are every candidate the name reaches. A name matching several definitions
reaches all of them rather than one picked by type or dispatch.

Repetition is kept, one pair per reference, so a reader counting distinct sources and one
summing references both take what they mean off the same walk. [`reach_graph`](@ref) reads
it as reachability.
"""
function reference_edges(files::Vector{ParsedFile}, table::SymbolTable, linkage::ResolvedLinkage)
    # The top-level function body ranges per file, a definition's index keyed by its
    # name-node identity, and the definitions sharing a file and name, the three lookups
    # the edges resolve against. A def carrying a function unit (`unit != 0`) is a
    # top-level function; one at file scope is a leaf. Same-file same-name definitions
    # resolve together: a reference binds lexically to one, but name resolution cannot
    # tell a type from its constructor or one method from its overload, so reaching one
    # reaches all, the within-file counterpart of the cross-file candidate split.
    file_by_path = Dict{String, ParsedFile}(f.file => f for f in files)
    topfns = Dict{String, Vector{Tuple{Int, Int, Int}}}()
    byid = Dict{Tuple{String, NodeId}, Int}()
    name_class = Dict{Tuple{String, String}, Vector{Int}}()
    for (i, d) in enumerate(table.defs)
        byid[(d.file, d.id)] = i
        push!(get!(() -> Int[], name_class, (d.file, d.name)), i)
        d.unit == 0 && continue
        from, to = unit_span(file_by_path[d.file].index.units[d.unit])
        push!(get!(() -> Tuple{Int, Int, Int}[], topfns, d.file), (from, to, i))
    end

    edges = Tuple{Int, Int}[]
    toplevel = Int[]
    empty_ranges = Tuple{Int, Int, Int}[]
    for f in files
        ranges = get(topfns, f.file, empty_ranges)
        for (refid, defid) in f.index.bindings
            target = get(byid, (f.file, defid), 0)
            target == 0 && continue
            record_reference!(
                edges, toplevel, enclosing_def(ranges, refid[1], refid[2]),
                name_class[(f.file, table.defs[target].name)]
            )
        end
    end
    for reference in linkage.references
        ranges = get(topfns, reference.file.file, empty_ranges)
        record_reference!(
            edges, toplevel, enclosing_def(ranges, reference.ref.id[1], reference.ref.id[2]),
            reference.candidates
        )
    end
    return edges, toplevel
end

"""
    reach_graph(files, table; linkage=resolve_linkage(files, table)) -> (adj, roots)

The forward reference graph over `table.defs` and the root set a dead-code search starts
from. `adj[i]` lists the definition indices definition `i` references; `roots` holds the
declared-public definitions and those referenced from top-level code. The edges are
[`reference_edges`](@ref) read as adjacency, and its top-level targets seed roots rather
than edges: code that runs unconditionally keeps alive whatever it names.

The cross-file edges and the public surface both come out of `linkage`, so a scan that has
already resolved the corpus does not resolve it again here.
"""
function reach_graph(
        files::Vector{ParsedFile}, table::SymbolTable;
        linkage::ResolvedLinkage = resolve_linkage(files, table)
    )
    n = length(table.defs)
    adj = [Int[] for _ in 1:n]
    roots = Set{Int}()
    file_by_path = Dict{String, ParsedFile}(f.file => f for f in files)
    surface = linkage.surface
    for (i, d) in enumerate(table.defs)
        link = get(LINKAGES, file_by_path[d.file].language, nothing)
        public = link === nothing || link.is_public(d, get(() -> Set{String}(), surface, d.file))::Bool
        (public || d.external_root) && push!(roots, i)
    end

    edges, toplevel = reference_edges(files, table, linkage)
    for (src, target) in edges
        push!(adj[src], target)
    end
    union!(roots, toplevel)
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
    cluster_unreferenced(files, table; linkage=resolve_linkage(files, table)) -> Vector{Finding}

Top-level definitions no path reaches from the corpus's public surface, reported as
`:unreferenced`, one finding per definition. Reachability follows [`reach_graph`](@ref):
declared-public definitions and those referenced from top-level code are roots, and the
within-file and cross-file reference edges carry liveness from there. An unreached
definition is necessarily private, so no public recheck is needed. Suppressed when its
line carries a `dendro-ignore: unreferenced` directive. Sound only over a whole module: a
definition referenced from a same-module file outside the scan is falsely flagged.

Pass a prebuilt `linkage` from [`resolve_linkage`](@ref) to share one resolution with a
caller that has already resolved the corpus.
"""
function cluster_unreferenced(
        files::Vector{ParsedFile}, table::SymbolTable;
        linkage::ResolvedLinkage = resolve_linkage(files, table)
    )
    findings = Finding[]
    adj, roots = reach_graph(files, table; linkage)
    seen = reachable(adj, roots)
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    for (i, d) in enumerate(table.defs)
        seen[i] && continue
        sup = is_suppressed(get(() -> Directive[], directives, d.file), d.line, RELATIONAL.unreferenced)
        push!(findings, Finding(RELATIONAL.unreferenced, [Location(d.file, d.line, d.name)], nothing, :high, nothing, :flag, sup))
    end
    sort!(findings; by = f -> (first(f.locations).file, first(f.locations).line))
    return findings
end
