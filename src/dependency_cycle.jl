# Dependency cycles in the corpus file graph, reported as the edges that break them.
#
# The literature is blunt about why this rule cannot be "your file is in a cycle": Melton
# and Tempero found around 45% of studied Java applications carry a cycle spanning 100 or
# more classes, so cycle membership describes most of a real codebase and separates
# nothing. A rule that fires that broadly would also make `errors` unsatisfiable, since a
# `:high` finding enters the gate floor. What is worth reporting is the small set of edges
# whose removal makes the component acyclic, because that names an edit.
#
# The cycle is found by Tarjan, the edges to cut by the Eades-Lin-Smyth heuristic weighted
# by reference count, so the arrangement it builds sends heavy dependencies forward and
# leaves the light ones pointing backwards. Cutting three edges carrying one reference each
# is a far better proposal than cutting one carrying two hundred.
#
# Structure only. The graph underneath resolves names lexically, gated by declared
# visibility; nothing here reads a type or a dispatch.

# Absolute band on the count of files caught in one cycle. Two files depending on each
# other is common and often deliberate, so the band sits well above it and the corpus
# percentile carries a small cycle that stands out against its corpus.
#
# Measured over nine corpora in five languages (this package, HTTP.jl, Pkg.jl, flask,
# requests, ripgrep, serde, guava, rails; 19 to 3483 files), the size at which a component
# stops admitting a bounded edit sits between seven and eight. Every component of seven
# files or fewer needed one to four cuts, inside `CYCLE_LOCATIONS_MAX`; every component of
# eight or more needed eight to 278. So `warn` sits at 5, where a component is still worth
# an edit and the report says which one, and `high` at 10, above which every component
# measured was a tangle: HTTP.jl's 24 files, flask's 18, Pkg.jl's 14, guava's 133, 25, 17
# and 13. That put seven findings at `high` across 4528 files, a floor a project can
# actually clear. Flagging cycle membership instead would have flagged 319 of those files,
# up to 84% of a single corpus.
#
# The percentile half fired on none of the nine. A corpus with enough components to rank
# against has many small ones, and they tie at a low rank; the half earns its place on the
# corpus holding one large cycle among a few small ones, which none of the nine was. So on
# real corpora this band, not the percentile, is doing the work.
const DEPENDENCY_CYCLE_BAND = (5, 10)

# The most locations one cycle finding carries. Past this a feedback set has stopped
# describing an edit an agent can make, and the finding switches to naming the tangle.
const CYCLE_LOCATIONS_MAX = 6

# The corpus needs this many cyclic components before the size percentile means anything;
# under it only the absolute band fires, as cohesion and placement do on a thin corpus.
# Without the floor a corpus holding one two-file cycle would rank it at the hundredth
# percentile and report it, which is the "everything is in a cycle" trap by another route.
const MIN_CYCLE_COMPONENTS = 5

# Tarjan's running state: the discovery index and low-link per node, the stack of nodes in
# the component being built, and the components closed so far. Carried as one record so the
# walk takes three arguments rather than seven.
mutable struct TarjanState
    index::Vector{Int}
    low::Vector{Int}
    onstack::Vector{Bool}
    stack::Vector{Int}
    next::Int
    components::Vector{Vector{Int}}
end

# The file graph's edges in a fixed order. `edges` is a `Dict`, so its iteration order is
# not the corpus order; every walk below reads this vector instead, which is what keeps the
# components, the arrangement, and the reported locations identical at any thread count.
# Sorted once per scan and threaded through, since each component would otherwise re-sort
# the whole corpus's edges.
edge_keys(fg::FileGraph) = sort!(collect(keys(fg.edges)))

# The file graph's successor lists, in node order.
function successors(fg::FileGraph, order::Vector{Tuple{Int, Int}})
    adj = [Int[] for _ in eachindex(fg.files)]
    for (src, dst) in order
        push!(adj[src], dst)
    end
    return adj
end

# The strongly connected components of `adj`, each sorted, in the order Tarjan closes them.
# A component of one node is a file that is not in a cycle at all.
function strong_components(adj::Vector{Vector{Int}})
    n = length(adj)
    st = TarjanState(zeros(Int, n), zeros(Int, n), fill(false, n), Int[], 0, Vector{Int}[])
    for v in 1:n
        st.index[v] == 0 && tarjan_visit!(st, adj, v)
    end
    return st.components
end

# Number `v` and put it on the component stack: the entry half of a depth-first visit.
function tarjan_enter!(st::TarjanState, v::Int)
    st.next += 1
    st.index[v] = st.next
    st.low[v] = st.next
    push!(st.stack, v)
    st.onstack[v] = true
    return nothing
end

# The depth-first walk from `root`, closing a component whenever it finishes a node whose
# low-link never reached an earlier one. Carries its own frame stack rather than recursing:
# the depth is the corpus file count, and a scan of a large enough repo would exhaust the
# call stack and throw where it has to report. Each frame is a node and the index of the
# next successor to walk, which is the whole of what the recursive form kept in a call
# frame.
#
# The order components close in is the recursive order, and every reader depends on it. A
# child's low-link travels to its parent as that child's frame pops, which is where the
# recursion assigned it on return, and before the parent's next successor is read.
function tarjan_visit!(st::TarjanState, adj::Vector{Vector{Int}}, root::Int)
    frames = Tuple{Int, Int}[(root, 1)]
    tarjan_enter!(st, root)
    while !isempty(frames)
        v, i = frames[end]
        succs = adj[v]
        if i <= length(succs)
            frames[end] = (v, i + 1)
            w = succs[i]
            if st.index[w] == 0
                tarjan_enter!(st, w)
                push!(frames, (w, 1))
            elseif st.onstack[w]
                st.low[v] = min(st.low[v], st.index[w])
            end
        else
            pop!(frames)
            st.low[v] == st.index[v] && push!(st.components, pop_component!(st, v))
            isempty(frames) || (p = first(frames[end]); st.low[p] = min(st.low[p], st.low[v]))
        end
    end
    return nothing
end

# The component rooted at `v`: everything above it on the stack, sorted so the membership
# does not depend on the order the walk happened to push.
function pop_component!(st::TarjanState, v::Int)
    comp = Int[]
    while true
        w = pop!(st.stack)
        st.onstack[w] = false
        push!(comp, w)
        w == v && break
    end
    return sort!(comp)
end

# One cyclic component as a graph in its own right, in local indices 1:k. `members` maps
# each back to its file-graph node, and `weight` holds the reference count on each internal
# edge. `incident` lists both directions at once, each entry the neighbour, the edge's
# weight, and whether the edge leaves this vertex: peeling a vertex has to reach its
# predecessors and its successors, and reading one list keeps that a single walk.
struct CycleSub
    members::Vector{Int}
    incident::Vector{Vector{Tuple{Int, Int, Bool}}}
    weight::Dict{Tuple{Int, Int}, Int}
end

# The subgraph `members` induces in `fg`. Edges leaving the component are dropped: the
# question is which edges inside it close the cycle.
function induced_subgraph(fg::FileGraph, members::Vector{Int}, order::Vector{Tuple{Int, Int}})
    k = length(members)
    local_of = Dict{Int, Int}(g => i for (i, g) in enumerate(members))
    sub = CycleSub(members, [Tuple{Int, Int, Bool}[] for _ in 1:k], Dict{Tuple{Int, Int}, Int}())
    for (src, dst) in order
        s = get(local_of, src, 0)
        d = get(local_of, dst, 0)
        (s == 0 || d == 0) && continue
        w = fg.edges[(src, dst)].weight
        push!(sub.incident[s], (d, w, true))
        push!(sub.incident[d], (s, w, false))
        sub.weight[(s, d)] = w
    end
    return sub
end

# The alive vertex whose weighted out-degree most exceeds its weighted in-degree, ties
# broken by the lower index so the arrangement never depends on iteration order.
function max_delta(alive::Vector{Bool}, outw::Vector{Int}, inw::Vector{Int})
    best, bestdelta = 0, typemin(Int)
    for v in eachindex(alive)
        alive[v] || continue
        delta = outw[v] - inw[v]
        delta > bestdelta && (best = v; bestdelta = delta)
    end
    return best
end

# The next vertex Eades-Lin-Smyth places, and the end of the arrangement it goes to. A sink
# goes to the right end and a source to the left, since neither can carry a backward edge.
# Absent either, the vertex whose weighted out-degree most exceeds its in-degree goes left:
# placing it there sends its heavy outgoing references forward, so what is left pointing
# backwards is the light traffic, which is the cheaper cut.
function next_vertex(alive::Vector{Bool}, outw::Vector{Int}, inw::Vector{Int})
    sink = findfirst(v -> alive[v] && outw[v] == 0, eachindex(alive))
    if sink !== nothing
        return (sink, :right)
    end
    source = findfirst(v -> alive[v] && inw[v] == 0, eachindex(alive))
    if source !== nothing
        return (source, :left)
    end
    return (max_delta(alive, outw, inw), :left)
end

# The position each vertex takes in the Eades-Lin-Smyth linear arrangement of `sub`: peel a
# vertex at a time onto one end or the other, updating the weighted degrees of what remains.
function linear_arrangement(sub::CycleSub)
    k = length(sub.members)
    outw = zeros(Int, k)
    inw = zeros(Int, k)
    for ((s, d), w) in sub.weight
        outw[s] += w
        inw[d] += w
    end
    alive = fill(true, k)
    left, right = Int[], Int[]
    for _ in 1:k
        v, side = next_vertex(alive, outw, inw)
        alive[v] = false
        push!(side === :left ? left : right, v)
        for (u, w, outgoing) in sub.incident[v]
            alive[u] || continue
            outgoing ? (inw[u] -= w) : (outw[u] -= w)
        end
    end
    pos = zeros(Int, k)
    for (i, v) in enumerate(append!(left, reverse!(right)))
        pos[v] = i
    end
    return pos
end

# The edges pointing backwards in the arrangement: removing them leaves the component
# acyclic. Eades-Lin-Smyth bounds this at `m/2 - k/6` edges in linear time, which is a
# guarantee about the size of the set and not about its being the smallest one. It is a
# heuristic, and the set it proposes is never presented as a minimum feedback arc set.
# Lightest first, so a capped report names the cheapest cuts.
function feedback_arcs(sub::CycleSub)
    pos = linear_arrangement(sub)
    arcs = Tuple{Int, Int}[e for e in sort!(collect(keys(sub.weight))) if pos[e[1]] > pos[e[2]]]
    sort!(arcs; by = e -> (sub.weight[e], e))
    return arcs
end

# The site of one proposed cut: the import statement admitting the edge where the language
# declares one, else the source file's representative line. The label names the edge to
# remove, so an agent reading the location knows which dependency to take out.
#
# The target is named relative to the source file's own directory, the way the import being
# removed already reads, and never as an absolute path. `fkey` (`gate.jl`) keys a finding on
# each location's `unit` verbatim while it makes the `file` repo-relative, and the ratchet
# scores the base revision in a `git archive` tempdir. An absolute target would differ
# between the two roots, so every cut finding would miss its base key and re-report as new
# on each run.
function cut_location(fg::FileGraph, sub::CycleSub, arc::Tuple{Int, Int})
    src, dst = sub.members[arc[1]], sub.members[arc[2]]
    edge = fg.edges[(src, dst)]
    line = isempty(edge.declared) ? fg.first_line[src] : edge.declared[1].line
    from = dirname(fg.files[src])
    return Location(fg.files[src], line, string("cut -> ", relpath(fg.files[dst], isempty(from) ? "." : from)))
end

# Where the fire is in a component no bounded edit untangles: the members carrying the most
# edges inside it, heaviest coupling breaking a tie, capped like the feedback set. Every
# label carries the cut count the locations have stopped naming, so the truncation says so
# rather than reading as a complete list of cuts.
function tangle_locations(fg::FileGraph, sub::CycleSub, cuts::Int)
    k = length(sub.members)
    edges_at = [length(sub.incident[v]) for v in 1:k]
    weight_at = zeros(Int, k)
    for ((s, d), w) in sub.weight
        weight_at[s] += w
        weight_at[d] += w
    end
    ranked = sort!(collect(1:k); by = v -> (-edges_at[v], -weight_at[v], fg.files[sub.members[v]]))
    label = string("tangled: ", cuts, " cuts")
    top = ranked[1:min(k, CYCLE_LOCATIONS_MAX)]
    return [Location(fg.files[sub.members[v]], fg.first_line[sub.members[v]], label) for v in top]
end

# The locations one component's finding carries: the cuts when the feedback set fits the
# cap, the tangle's busiest members when it does not. A strongly connected component of two
# or more files holds a cycle, so the feedback set is never empty and the finding always has
# somewhere to point.
function cycle_locations(fg::FileGraph, members::Vector{Int}, order::Vector{Tuple{Int, Int}})
    sub = induced_subgraph(fg, members, order)
    arcs = feedback_arcs(sub)
    length(arcs) <= CYCLE_LOCATIONS_MAX && return Location[cut_location(fg, sub, e) for e in arcs]
    return tangle_locations(fg, sub, length(arcs))
end

"""
    cluster_dependency_cycles(files, fg; band=$DEPENDENCY_CYCLE_BAND, cut=0.95, min_components=$MIN_CYCLE_COMPONENTS) -> Vector{Finding}

Files caught in a dependency cycle, reported as `:dependency_cycle` through the edges that
break it. Tarjan finds the strongly connected components of the file graph `fg`, and each
component of two or more files is one finding. The score is the component size, carrying
the absolute `band` and the corpus percentile over the sizes of every cyclic component,
fired when either trips. Under `min_components` scored components the percentile is
withheld and only the band fires. Measured over nine corpora the percentile half never
fired: small cycles are numerous enough on a corpus large enough to rank against that they
tie low, so the band carries this metric in practice.

The finding is never "this file is in a cycle". Melton and Tempero measured cycles
spanning a hundred classes in around 45% of the Java applications they studied, so
membership describes most of a codebase and names no edit, and a rule that fires that
broadly would take the `errors` gate floor with it. What the finding names instead is the
**feedback arc set**: the edges whose removal would make the component acyclic, found by
the Eades-Lin-Smyth heuristic weighted by reference count so it prefers cutting the light
edges. Each location is one cut, pointing at the import statement admitting the edge where
the language declares one, labelled `cut -> <target>`.

# The heuristic is a heuristic

Eades-Lin-Smyth bounds the size of the set it returns and runs in linear time. It does not
return a minimum feedback arc set, and nothing here should be read as claiming it does. A
different arrangement may cut fewer edges.

# Two kinds of finding

When the feedback set exceeds `CYCLE_LOCATIONS_MAX`, the component has no bounded edit and
the finding switches kind: the locations become the component's highest-degree members and
every label reads `tangled: <n> cuts`. The alternative was to drop the finding, on the
grounds that a two-hundred-file tangle proposes no edit an agent can make. Reporting it is
the honest-over-silent call: silently dropping the worst architectural problem in a corpus
is worse than reporting one that says plainly it is not an edit. The label is what makes
the two kinds tell apart without inferring anything from the location count, and it carries
the true cut count so a truncated report reads as truncated.

That cut count sits in each location's `unit` field, which `fkey` (`gate.jl`) reads, so a
tangle growing from twelve cuts to thirteen re-keys and the ratchet reports it as new. This
is the trade `:back_edge` and `:hub` make, and for the same reason: the count is part of
what the finding claims, so a gate that stayed quiet through a change to it would be
reporting a stale reading. More edges to cut is worsening, and the ratchet is there to catch
worsening.

# Failure modes

- Mutually recursive modules by design, common in parsers and interpreters. Answer with
  `dendro-ignore: dependency_cycle`, not a smarter model.
- Test fixtures carrying an intentional cycle. Answer with `ignore` patterns.
- A language whose visibility model unions a whole inclusion component, Julia's `include`
  among them, lets references run both ways between files that a language with directed
  imports would keep one-way. Cycles are correspondingly easier to form there.
"""
function cluster_dependency_cycles(
        files::Vector{ParsedFile}, fg::FileGraph;
        band::Tuple{Int, Int} = DEPENDENCY_CYCLE_BAND, cut::Real = 0.95,
        min_components::Integer = MIN_CYCLE_COMPONENTS
    )
    findings = Finding[]
    order = edge_keys(fg)
    comps = Vector{Int}[c for c in strong_components(successors(fg, order)) if length(c) >= 2]
    isempty(comps) && return findings

    sizes = sort([length(c) for c in comps])
    enough = length(comps) >= min_components
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    for members in comps
        score = length(members)
        absolute, pct = two_scores(score, sizes, band, enough)
        fires(absolute, pct, cut) || continue
        locations = cycle_locations(fg, members, order)
        anchor = locations[1]
        sup = is_suppressed(
            get(() -> Directive[], directives, anchor.file), anchor.line, RELATIONAL.dependency_cycle
        )
        push!(findings, Finding(RELATIONAL.dependency_cycle, locations, score, absolute, pct, :scalar, sup))
    end
    sort!(findings; by = f -> (-something(f.value, 0), first(f.locations).file, first(f.locations).line))
    return findings
end
