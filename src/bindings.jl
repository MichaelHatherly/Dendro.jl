# Lexical scope resolution. A second per-language query (`<lang>.scopes.scm`) tags
# scope regions, name-introducing definitions, and references; this resolver binds
# each reference to the in-file definition it resolves to, the nearest enclosing
# definition of the same name. It stays within one file's tree: no cross-file
# resolution, no types, no dispatch. The binding map feeds the cohesion metric,
# which links functions that reference a common file-local name. Scope membership
# is geometric, from byte ranges, so the flattening `each_capture` does to matches
# costs nothing here.

# A scope region: its byte span and the definitions introduced directly in it,
# keyed by name text.
struct ScopeEntry
    from::Int
    to::Int
    defs::Dict{String, TreeSitter.Node}
    # Typed constructor so the only method takes concrete arguments: the default
    # `Any`-accepting one would convert each field, which reads as a possible throw.
    ScopeEntry(from::Int, to::Int, defs::Dict{String, TreeSitter.Node}) = new(from, to, defs)
end

# Definition kinds whose name binds in the enclosing scope, not their own. A
# function, type, or macro is visible to its siblings, so a call from one sibling
# to another resolves to it. Other kinds (locals, consts) bind in their own scope.
const HOISTED_KINDS = ("function", "struct", "macro")

# A `definition.<kind>` capture is hoisted when its kind is one of HOISTED_KINDS.
function is_hoisted(capture::AbstractString)
    for k in HOISTED_KINDS
        endswith(capture, k) && return true
    end
    return false
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
# no in-file definition (an import, a builtin).
function lookup_definition(scopes::Vector{ScopeEntry}, from::Int, to::Int, name::AbstractString)
    best = nothing
    best_span = typemax(Int)
    for s in scopes
        (s.from <= from && to <= s.to) || continue
        span = s.to - s.from
        span < best_span || continue
        d = get(s.defs, name, nothing)
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
left unbound.
"""
function resolve_bindings!(
        bindings::Dict{NodeId, NodeId}, tree::TreeSitter.Tree,
        query::TreeSitter.Query, source::AbstractString
    )
    scopes = ScopeEntry[]
    defnodes = TreeSitter.Node[]
    defhoist = Bool[]
    refnodes = TreeSitter.Node[]
    defids = Set{NodeId}()
    for cap in TreeSitter.each_capture(tree, query, source)
        name = TreeSitter.capture_name(query, cap)
        if name == "scope"
            from, to = TreeSitter.byte_range(cap.node)
            push!(scopes, ScopeEntry(from, to, Dict{String, TreeSitter.Node}()))
        elseif name == "reference"
            push!(refnodes, cap.node)
        else
            push!(defnodes, cap.node)
            push!(defhoist, is_hoisted(name))
            push!(defids, nodeid(cap.node))
        end
    end
    isempty(scopes) && return bindings
    for (i, d) in enumerate(defnodes)
        from, to = TreeSitter.byte_range(d)
        owner = owning_scope(scopes, from, to, defhoist[i])
        owner === nothing && continue
        name = String(strip(TreeSitter.slice(source, d)))
        get!(owner.defs, name, d)
    end
    sizehint!(bindings, length(refnodes))
    for r in refnodes
        rid = nodeid(r)
        rid in defids && continue
        from, to = TreeSitter.byte_range(r)
        name = String(strip(TreeSitter.slice(source, r)))
        d = lookup_definition(scopes, from, to, name)
        d === nothing && continue
        bindings[rid] = nodeid(d)
    end
    return bindings
end
