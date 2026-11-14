# Lexical scope resolution. A second per-language query (`<lang>.scopes.scm`) tags
# scope regions, name-introducing definitions, and references; this resolver binds
# each reference to the in-file definition it resolves to, the nearest enclosing
# definition of the same name. It stays within one file's tree: no cross-file
# resolution, no types, no dispatch. The binding map feeds the cohesion metric,
# which links functions that reference a common file-local name. Scope membership
# is geometric, from byte ranges, so the flattening `each_capture` does to matches
# costs nothing here.

# A scope region: its byte span and the definitions introduced directly in it,
# keyed by name text. `types` holds those in a language's separate type namespace, a
# TypeScript interface beside a same-named const, and stays empty where there is none.
struct ScopeEntry
    from::Int
    to::Int
    defs::Dict{String, TreeSitter.Node}
    types::Dict{String, TreeSitter.Node}
    # Typed constructor so the only method takes concrete arguments: the default
    # `Any`-accepting one would convert each field, which reads as a possible throw.
    ScopeEntry(from::Int, to::Int) = new(from, to, Dict{String, TreeSitter.Node}(), Dict{String, TreeSitter.Node}())
end

# Definition kinds whose name binds in the enclosing scope, not their own. A
# function, named type, class, or macro is visible to its siblings, so a call from
# one sibling to another resolves to it. A property, a field declared by a constructor
# parameter, binds in the class body enclosing that constructor. Other kinds (locals,
# consts, fields declared in the body) bind in their own scope.
const HOISTED_KINDS = ("function", "struct", "macro", "class", "property")

# Definition kinds that bind a local variable. Julia splits them: `:local` is a
# fresh-binding form (a `for`/`let` head), `:assign` a statement assignment that
# rebinds an enclosing local when one carries the name. Languages without the
# split capture every local as `:local`.
const LOCAL_KINDS = (:local, :assign)

# A `definition.<kind>` capture is hoisted when its kind is one of HOISTED_KINDS.
function is_hoisted(capture::AbstractString)
    for k in HOISTED_KINDS
        endswith(capture, k) && return true
    end
    return false
end

# The kind of a `definition.<kind>` capture as a symbol, e.g. "definition.function"
# becomes `:function`. The corpus symbol table reads it to tell a function from a type
# from a const.
function def_kind(capture::AbstractString)
    i = findlast('.', capture)
    return Symbol(i === nothing ? capture : capture[nextind(capture, i):end])
end

# The scope, definition, and reference nodes a scopes query tags over one tree. The
# binding resolver and the corpus symbol table both read it, so the capture walk runs
# once per consumer. `defhoist`, `defkinds` and `deftype` are parallel to `defnodes`,
# `reftype` to `refnodes`: a `@definition.type.<kind>` lives in the type namespace and a
# `@reference.type` sits in a type position. `importids` holds the definitions of kind
# `:import`, a name bound here to a definition in another file.
struct ScopeCaptures
    scopes::Vector{ScopeEntry}
    defnodes::Vector{TreeSitter.Node}
    defhoist::Vector{Bool}
    defkinds::Vector{Symbol}
    deftype::Vector{Bool}
    refnodes::Vector{TreeSitter.Node}
    reftype::Vector{Bool}
    defids::Set{NodeId}
    importids::Set{NodeId}
    # An empty captures set, filled in place by `collect_scopes`, and the value a
    # `QueryIndex` carries for a file with no scopes query or no scope regions. Taking no
    # arguments, it converts none, where the default constructor converts every field.
    ScopeCaptures() = new(
        ScopeEntry[], TreeSitter.Node[], Bool[], Symbol[], Bool[], TreeSitter.Node[], Bool[],
        Set{NodeId}(), Set{NodeId}(),
    )
end

# Walk a scopes query's captures once: scope regions, name-introducing definitions
# with their hoist flag and kind, and references. The second pass that assigns
# definitions to scopes lives in `assign_defs!`, since the symbol table places them
# differently.
function collect_scopes(tree::TreeSitter.Tree, query::TreeSitter.Query, source::AbstractString)
    caps = ScopeCaptures()
    for cap in TreeSitter.each_capture(tree, query, source)
        name = TreeSitter.capture_name(query, cap)
        if name == "scope"
            from, to = TreeSitter.byte_range(cap.node)
            push!(caps.scopes, ScopeEntry(from, to))
        elseif name == "reference" || name == "reference.type"
            push!(caps.refnodes, cap.node)
            push!(caps.reftype, name == "reference.type")
        elseif !startswith(name, "_")  # an `@_` capture only feeds a predicate
            push!(caps.defnodes, cap.node)
            push!(caps.defhoist, is_hoisted(name))
            kind = def_kind(name)
            push!(caps.defkinds, kind)
            push!(caps.deftype, startswith(name, "definition.type."))
            push!(caps.defids, nodeid(cap.node))
            kind === :import && push!(caps.importids, nodeid(cap.node))
        end
    end
    return caps
end

# Assign each definition to its owning scope, hoisting functions, types, and macros to
# the enclosing scope so siblings resolve to them. First name in a scope wins.
function assign_defs!(caps::ScopeCaptures, source::AbstractString)
    for (i, d) in enumerate(caps.defnodes)
        from, to = TreeSitter.byte_range(d)
        owner = owning_scope(caps.scopes, from, to, caps.defhoist[i])
        owner === nothing && continue
        name = String(strip(TreeSitter.slice(source, d)))
        get!(caps.deftype[i] ? owner.types : owner.defs, name, d)
    end
    return caps
end

# The scope a definition belongs to: the innermost scope containing it, or, when
# the definition is hoisted, the scope enclosing that one. `nothing` when no scope
# contains it, or when a hoisted definition has no enclosing scope (it keeps the
# innermost).
function owning_scope(scopes::Vector{ScopeEntry}, from::Int, to::Int, hoist::Bool)
    inner = nothing
    inner_span = typemax(Int)
    for s in scopes
        if s.from <= from && to <= s.to
            span = s.to - s.from
            if span < inner_span
                inner = s
                inner_span = span
            end
        end
    end
    inner === nothing && return nothing
    hoist || return inner
    parent = nothing
    parent_span = typemax(Int)
    for s in scopes
        if s.from <= from && to <= s.to
            span = s.to - s.from
            if span > inner_span && span < parent_span
                parent = s
                parent_span = span
            end
        end
    end
    return parent === nothing ? inner : parent
end

# The definition a reference at `[from,to]` resolves to: the nearest enclosing scope
# that defines `name`, by smallest containing span, or `nothing` for a free name with
# no in-file definition (an import, a builtin). A reference in a type position tries the
# type namespace first and falls back to the values, where a class declares its type.
function lookup_definition(scopes::Vector{ScopeEntry}, from::Int, to::Int, name::AbstractString, type::Bool = false)
    if type
        d = nearest_definition(scopes, from, to, name, true)
        d === nothing || return d
    end
    return nearest_definition(scopes, from, to, name, false)
end

function nearest_definition(scopes::Vector{ScopeEntry}, from::Int, to::Int, name::AbstractString, types::Bool)
    best = nothing
    best_span = typemax(Int)
    for s in scopes
        (s.from <= from && to <= s.to) || continue
        span = s.to - s.from
        span < best_span || continue
        d = get(types ? s.types : s.defs, name, nothing)
        d === nothing && continue
        best = d
        best_span = span
    end
    return best
end

"""
    resolve_bindings!(bindings, tree, query, source) -> bindings

Fill `bindings` with each reference node's identity mapped to the identity of the
in-file definition it resolves to, running `query` (a language's scopes query) over
`tree`. A definition is assigned to its scope, hoisted to the enclosing scope for
functions, types, and macros so siblings resolve to it; each reference binds to the
nearest enclosing definition of its name. References with no in-file definition are
left unbound. A reference resolving to an import goes into `imports` instead, since its
definition lives in another file.
"""
function resolve_bindings!(
        bindings::Dict{NodeId, NodeId}, tree::TreeSitter.Tree,
        query::TreeSitter.Query, source::AbstractString,
        imports::Dict{NodeId, NodeId} = Dict{NodeId, NodeId}()
    )
    caps = collect_scopes(tree, query, source)
    isempty(caps.scopes) && return bindings
    assign_defs!(caps, source)
    return resolve_bindings!(bindings, caps, source, imports)
end

# Resolve references against an already-collected, scope-assigned captures set, the
# path that reuses the cached `ScopeCaptures` on a `QueryIndex` so the capture walk and
# scope assignment are not repeated.
function resolve_bindings!(
        bindings::Dict{NodeId, NodeId}, caps::ScopeCaptures, source::AbstractString,
        imports::Dict{NodeId, NodeId} = Dict{NodeId, NodeId}()
    )
    sizehint!(bindings, length(caps.refnodes))
    for (i, r) in enumerate(caps.refnodes)
        rid = nodeid(r)
        rid in caps.defids && continue
        from, to = TreeSitter.byte_range(r)
        name = String(strip(TreeSitter.slice(source, r)))
        d = lookup_definition(caps.scopes, from, to, name, caps.reftype[i])
        d === nothing && continue
        did = nodeid(d)
        did in caps.importids ? (imports[rid] = did) : (bindings[rid] = did)
    end
    return bindings
end
