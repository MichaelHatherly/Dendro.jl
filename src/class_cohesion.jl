# Class-level cohesion. `:low_cohesion` asks whether a file holds several independent
# concerns; this asks it of a class, the level LCOM4 was defined at. A class's methods
# form a graph: two are linked when they touch a field of the same instance, or when one
# calls the other. A class breaking into several components holds that many independent
# concerns behind one name, and the edit it names is the class split along them.
#
# Syntactic and name-based like the rest. The methods are the callable units one class
# node holds, the fields the `self.x`/`this.x`/`@x` use sites its query tags, and the call
# edges the `@callee` names `callees_by_unit` already attributes. Nothing resolves a type
# or a dispatch, which is why the reading exists only for the languages whose methods live
# inside the class that owns them: python, java, javascript, typescript, php, ruby and
# rust. Julia is out by the same line the rest of the package draws, a struct's methods
# being whatever dispatches on it anywhere; Go and C put receiver methods at file scope
# with no container node to read; a C++ class declares its methods and defines them out of
# line, so the in-class node holds almost none of them and the count would measure the
# header split rather than the class.
#
# The constructor is the one method the rule drops. It assigns every field a class has, so
# counting it would link every group to every other and read every class as one concern.
# That exclusion is also why there is no ubiquity cut here: a field every method touches is
# the shape that hides a real split (a `self._lock` makes a divided class read cohesive),
# and dropping such a field would be the cut for it, but at class scale the population is
# too small for a share to mean anything. The constructor exclusion is what buys back most
# of the same ground.
#
# A class whose methods name no field at all is not scored. There the count is the method
# count and the reading is vacuous: a static utility class, a Rust `impl Trait` over a unit
# struct, an abstract base whose methods all throw. Measurement puts the size of that: the
# gate took guava's worst score from 79 to 28 and ripgrep's median from 6 to 2.
#
# Two exclusions measured and one kept. Dropping trivial accessors, a short body with no
# call and at most one field, moved the per-corpus p95 from 12 to 11 on guava and 15.5 to
# 13.7 on flask, so it does not pay for the language-specific judgement of what an accessor
# is, and v1 keeps them. Dropping constructors moved flask's p95 from 12.4 to 15.5 and left
# guava's where it was, a smaller effect than expected, but it stays: a constructor links
# every group to every other by definition rather than by evidence.

# Absolute band on the number of independent components a class's methods fall into.
#
# Measured over 828 classes in five corpora across four languages: guava, flask, requests,
# fastmcp and ripgrep. Independence is ordinary. The median class scores 2 or 3 in every
# one of them, so methods falling into a few groups is what working code looks like, and
# the tail is long: the per-corpus p95 runs from 5.6 to 15.5 and the p99 from 8 to 21.5. So
# `warn` at 13 sits above the p95 of four of the five and `high` at 22 above the p99 of all
# five, the shape `:distant_definition` and `:hub` take.
#
# The band cannot go lower and the hand reading is what says so. Of the 29 guava classes at
# or above 13, sixteen are static utility classes, abstract bases and forwarding wrappers,
# shapes holding a constant or two where the score reads the method count. Nine more are
# public API classes whose static factories sit beside their instance methods, a split
# nobody would make. Three or four name a real god class, `LocalCache` at 24 components over
# 90 methods among them. flask is cleaner at this band: one of its 16 scored classes reports
# and it is the application base class, with the next one down a second true positive.
#
# That ratio is why the rule ships off by default. Nothing syntactic separates a utility
# class holding one constant from a class whose state has come apart, so what is left to
# read is how many groups there are. A project that wants the reading turns it on with
# `[rules] divisible_class = true` and sets `[bands] divisible_class` to what its own
# classes look like, which is the layer the opinion belongs in.
const DIVISIBLE_CLASS_BAND = (13, 22)

# A class with fewer methods than this is too small to read as several concerns. Swept over
# 2, 3, 4 and 6 against the same five corpora: at 2 and 3 the median score is 2, the
# smallest a class can report, so the count tracks how many methods there are rather than
# how they group. At 4 the per-corpus medians separate, and at 6 the population halves for
# no further separation.
const MIN_CLASS_METHODS = 4

# The corpus needs this many scored classes before the component-count percentile means
# anything; under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_DIVISIBLE_CLASS_COUNT = 5

# The `@class` nodes in one file, in source order, and their spans, the containment table
# the method attribution scans. Shaped as `unit_ranges` so `containing_unit` reads either.
class_nodes(index::QueryIndex) = sort(index.class.nodes; by = TreeSitter.byte_range)

# Whether `inner` is contained by `outer`, the byte-span test the class and method
# attribution share.
inside(inner::Tuple{Int, Int}, outer::Tuple{Int, Int}) =
    outer[1] <= inner[1] && inner[2] <= outer[2]

# Each class's methods, as unit indices, in `class_nodes` order. A unit is a method of
# the innermost class containing it, so a nested class takes its own; a unit nested inside
# a callable that is itself inside the class is that callable's business rather than a
# method of its own, which is what keeps a closure out of the method set. Constructors are
# dropped here, the one place the rule drops a method.
function class_methods(index::QueryIndex, classes::Vector{Tuple{Int, Int}}, ranges::Vector{Tuple{Int, Int}})
    out = [Int[] for _ in classes]
    for (i, u) in enumerate(units(index))
        is_callable(u, index) || continue
        unit_node(u) in index.constructor && continue
        span = ranges[i]
        ci = containing_unit(classes, span[1], span[2])
        ci == 0 && continue
        enclosing = enclosing_unit(ranges, i)
        (enclosing != 0 && inside(ranges[enclosing], classes[ci])) && continue
        push!(out[ci], i)
    end
    return out
end

# The innermost unit strictly containing unit `i`, or 0. `containing_unit` answers with
# the unit itself, which is the wrong answer when the question is what encloses it.
function enclosing_unit(ranges::Vector{Tuple{Int, Int}}, i::Int)
    best, best_span = 0, typemax(Int)
    for (j, r) in enumerate(ranges)
        (j != i && inside(ranges[i], r) && r != ranges[i]) || continue
        span = r[2] - r[1]
        span < best_span || continue
        best, best_span = j, span
    end
    return best
end

# Each unit's `@field` texts, attributed to the innermost unit holding them, the same
# attribution `callees_by_unit` gives a call.
function fields_by_unit(index::QueryIndex)
    out = [Set{String}() for _ in units(index)]
    isempty(index.field.nodes) && return out
    ranges = unit_ranges(index)
    for n in index.field.nodes
        nid = nodeid(n)
        ui = containing_unit(ranges, nid[1], nid[2])
        ui == 0 && continue
        push!(out[ui], String(strip(TreeSitter.slice(index.source, n))))
    end
    return out
end

# Each unit's references to a name some class in the file declares as a field and that no
# in-file definition binds. Java alone lets a method name a field bare, and Java alone
# captures `@field_name`, so the gate is the data rather than a language check. A
# reference the bindings resolve is a local shadowing the field and names no field use.
# The resolver leaves a definition's own name unbound as well, so those are skipped too:
# declaring a local called `a` is not a use of the field `a`.
#
# Only a local shadows a field. Java lets a field and its accessor share a name, and the
# resolver hoists a method into the class scope, so `return hits` in `long hits()` binds to
# the method. Reading any binding as a shadow would then blind the rule to every getter
# written that way, which is most of them.
function bare_fields_by_unit(index::QueryIndex)
    out = [Set{String}() for _ in units(index)]
    isempty(index.field_name.nodes) && return out
    declared = Set{String}(text_of(index, n) for n in index.field_name.nodes)
    caps = index.scope_captures
    locals = Set{NodeId}(
        nodeid(n) for (n, kind) in zip(caps.defnodes, caps.defkinds) if kind in LOCAL_KINDS
    )
    ranges = unit_ranges(index)
    for r in caps.refnodes
        nid = nodeid(r)
        (nid in caps.defids || get(index.bindings, nid, nid) in locals) && continue
        name = text_of(index, r)
        name in declared || continue
        ui = containing_unit(ranges, nid[1], nid[2])
        ui == 0 && continue
        push!(out[ui], name)
    end
    return out
end

# One class's declared field names, the set a bare reference has to match to count.
declared_fields(index::QueryIndex, span::Tuple{Int, Int}) =
    Set{String}(text_of(index, n) for n in index.field_name.nodes if inside(TreeSitter.byte_range(n), span))

# A node's source text, trimmed.
text_of(index::QueryIndex, n::TreeSitter.Node) = String(strip(TreeSitter.slice(index.source, n)))

# What one class's methods touch and what they call, both in `methods` order. `per_unit`
# pairs the file's per-unit field sets with its per-unit callee sets, and a method takes
# its own entries plus those of every unit nested in it: a closure inside a method does the
# method's work, so what it touches is the method's.
function method_state(
        ranges::Vector{Tuple{Int, Int}}, methods::Vector{Int},
        per_unit::Tuple{Vector{Set{String}}, Vector{Set{String}}, Vector{Set{String}}},
        declared::Set{String}
    )
    fields, bare, callees = per_unit
    k = length(methods)
    mine = [Set{String}() for _ in 1:k]
    calls = [Set{String}() for _ in 1:k]
    mranges = Tuple{Int, Int}[ranges[m] for m in methods]
    for i in eachindex(ranges)
        owner = containing_unit(mranges, ranges[i][1], ranges[i][2])
        owner == 0 && continue
        union!(mine[owner], fields[i])
        union!(mine[owner], intersect(bare[i], declared))
        union!(calls[owner], callees[i])
    end
    return mine, calls
end

# One class's method graph as an undirected adjacency, in method order: two methods link
# when their field sets meet or one names the other.
function method_adjacency(mine::Vector{Set{String}}, calls::Vector{Set{String}}, names::Vector{String})
    k = length(mine)
    adj = [Dict{Int, Float64}() for _ in 1:k]
    for i in 1:k, j in (i + 1):k
        linked = !isdisjoint(mine[i], mine[j]) ||
            (!isempty(names[j]) && names[j] in calls[i]) ||
            (!isempty(names[i]) && names[i] in calls[j])
        linked || continue
        adj[i][j] = 1.0
        adj[j][i] = 1.0
    end
    return adj
end

# Whether any method of the class names a field. Written as a loop over a concrete
# element type rather than `all(isempty, mine)`, which the sound analyser reads as a
# function-valued argument returning `Any` in boolean context.
function any_state(mine::Vector{Set{String}})
    for own in mine
        isempty(own) || return true
    end
    return false
end

# One representative method per component, earliest line first: within a component the
# earliest-line method, and the components ordered by that line. `lines` is each method's
# first line, indexed as the components are. The shape `component_reps` takes over the
# corpus graph, over a class's local method positions here.
function method_reps(lines::Vector{Int}, comps::Vector{Vector{Int}})
    keyed = Tuple{Int, Int}[]
    for group in comps
        rep = group[1]
        for m in group
            lines[m] < lines[rep] && (rep = m)
        end
        push!(keyed, (lines[rep], rep))
    end
    sort!(keyed)
    return Int[m for (_, m) in keyed]
end

"""
    cluster_divisible_class(files; band=$DIVISIBLE_CLASS_BAND, cut=0.95, min_classes=$MIN_DIVISIBLE_CLASS_COUNT, min_methods=$MIN_CLASS_METHODS) -> Vector{Finding}

Classes whose methods split into several independent concerns, reported as
`:divisible_class`. Two methods are linked when they name a field of the same instance or
one calls the other, and the score is the number of connected components the class's
methods fall into, the LCOM4 reading at class scale. Each finding carries the absolute
`band` on that count and the corpus percentile over every scored class, fired when either
trips. The first location is the class, where a `dendro-ignore` goes; the rest are one
representative method per component, earliest first.

Two classes are never scored: one with fewer than `min_methods` methods, too small to read
as several concerns, and one whose methods name no field at all, where the count is the
method count and the question does not apply. A class of one component names nothing to
split, so it never reports, but it stays in the percentile population. Constructors are
dropped from the method set, since a constructor assigns every field and would link every
group to every other.

Within one class and name-based: the methods, fields and calls all come from one
syntactic container, and no type or dispatch is resolved. A language whose query tags no
`@class` scores nothing, which is Julia, Go, C and C++.

Off by default, since a class with no state to divide reads the same as one whose state has
come apart. [`analyze`](@ref) runs it only under `[rules] divisible_class = true`; the
band comment on `DIVISIBLE_CLASS_BAND` carries the measurement behind that.
"""
function cluster_divisible_class(
        files::Vector{ParsedFile}; band::Tuple{Int, Int} = DIVISIBLE_CLASS_BAND,
        cut::Real = 0.95, min_classes::Integer = MIN_DIVISIBLE_CLASS_COUNT,
        min_methods::Int = MIN_CLASS_METHODS
    )
    scored = Tuple{ParsedFile, Int, Vector{Location}}[]
    for f in files
        index = f.index
        isempty(index.class.nodes) && continue
        nodes = class_nodes(index)
        classes = Tuple{Int, Int}[TreeSitter.byte_range(n) for n in nodes]
        ranges = unit_ranges(index)
        per_unit = (fields_by_unit(index), bare_fields_by_unit(index), callees_by_unit(index))
        for (ci, methods) in enumerate(class_methods(index, classes, ranges))
            length(methods) >= min_methods || continue
            mine, calls = method_state(ranges, methods, per_unit, declared_fields(index, classes[ci]))
            any_state(mine) || continue
            names = String[unit_name(units(index)[m], index) for m in methods]
            adj = method_adjacency(mine, calls, names)
            lines = Int[units(index)[m].firstline for m in methods]
            reps = method_reps(lines, components(adj, collect(eachindex(methods))))
            node = nodes[ci]
            locations = Location[Location(f.file, line_of(node), held_class_name(node, index))]
            for r in reps
                u = units(index)[methods[r]]
                push!(locations, Location(f.file, u.firstline, unit_name(u, index)))
            end
            push!(scored, (f, length(reps), locations))
        end
    end
    return scored_findings(RELATIONAL.divisible_class, scored, band, cut, min_classes; min_reported = 2)
end

# A class's declared name, read off the `@def_name` the class node holds. A JavaScript
# class expression holds none and takes the name it is bound to, the same fallback a bound
# anonymous callable takes.
function held_class_name(node::TreeSitter.Node, index::QueryIndex)
    own = held_def_name(node, index)
    return isempty(own) ? binder_def_name(node, index) : own
end
