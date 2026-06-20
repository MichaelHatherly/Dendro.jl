# Corpus-wide symbol resolution. The per-file binding resolver (`bindings.jl`) leaves
# a reference unbound when its definition lives in another file. This builds the table
# those references resolve against: every top-level definition across the corpus, keyed
# by language, enclosing module path, and name. Name-based and lexical, never typed: it
# records what a name is declared as, not what a call dispatches to. The file boundary
# is crossed; the symbol-resolution one is not.

# A namespace region: its byte span and name, a Julia `module`, a Rust `mod`, a C++
# `namespace`. The scopes query cannot tell one from an ordinary block scope (both are
# @scope there), so a linkage query tags it with @module and its name with @module.name.
struct ModuleRegion
    from::Int
    to::Int
    name::String
end

# A top-level definition somewhere in the corpus: the file it lives in, its identity in
# that file's tree, the bound name and kind, the enclosing module path (outermost
# first), whether linkage makes it visible to other files, the function-unit index it
# belongs to (0 for a type or const outside any unit), and its source line.
struct CorpusDef
    file::String
    id::NodeId
    name::String
    kind::Symbol
    module_path::Vector{String}
    exported::Bool
    unit::Int
    line::Int
end

# Every corpus definition, indexed by (language, module path, name) so a reference
# resolves only against names declared in a module it can see, and two same-named defs
# in different modules never collide.
struct SymbolTable
    by_name::Dict{Tuple{Symbol, Vector{String}, String}, Vector{Int}}
    defs::Vector{CorpusDef}
end
SymbolTable() = SymbolTable(Dict{Tuple{Symbol, Vector{String}, String}, Vector{Int}}(), CorpusDef[])

# Definition kinds that name a top-level, corpus-visible symbol. Locals bind inside a
# function scope and never reach another file, so they are not indexed.
const SYMBOL_KINDS = (:function, :struct, :macro, :class, :const)
is_symbol_kind(kind::Symbol) = kind in SYMBOL_KINDS

# The namespace regions a linkage query tags over one tree, each paired with its name.
# @module marks the region, @module.name the name identifier; a name binds to the
# innermost region containing it, so a `module` named only by a nested block keeps its
# own name. Regions with no captured name keep an empty string.
function module_regions(tree::TreeSitter.Tree, query::TreeSitter.Query, source::AbstractString)
    spans = Tuple{Int, Int}[]
    namenodes = TreeSitter.Node[]
    for cap in TreeSitter.each_capture(tree, query, source)
        name = TreeSitter.capture_name(query, cap)
        if name == "module"
            push!(spans, TreeSitter.byte_range(cap.node))
        elseif name == "module.name"
            push!(namenodes, cap.node)
        end
    end
    labels = fill("", length(spans))
    for nc in namenodes
        nf, nt = TreeSitter.byte_range(nc)
        best = 0
        best_span = typemax(Int)
        for (k, (sf, st)) in enumerate(spans)
            (sf <= nf && nt <= st) || continue
            span = st - sf
            span < best_span || continue
            best = k
            best_span = span
        end
        best == 0 && continue
        isempty(labels[best]) && (labels[best] = String(strip(TreeSitter.slice(source, nc))))
    end
    return ModuleRegion[ModuleRegion(spans[k][1], spans[k][2], labels[k]) for k in eachindex(spans)]
end

# The module path of a definition at `[from, to]`: the names of every region containing
# it, outermost (largest span) first. Empty at file scope.
function module_path_of(regions::Vector{ModuleRegion}, from::Int, to::Int)
    containing = ModuleRegion[r for r in regions if r.from <= from && to <= r.to]
    sort!(containing; by = r -> r.from - r.to)
    return String[r.name for r in containing]
end

# The scope with the largest span, the file root: the namespace a file-level definition
# belongs to when no module encloses it.
function root_scope(scopes::Vector{ScopeEntry})
    best = scopes[1]
    best_span = best.to - best.from
    for s in scopes
        span = s.to - s.from
        span > best_span && (best = s; best_span = span)
    end
    return best
end

# Add one file's top-level definitions to `table`. A definition is top-level when its
# owning scope, hoisted for functions and types, is a namespace: the file root or a
# module region. That excludes a helper defined inside another function, whose owning
# scope is that function.
function file_symbols!(table::SymbolTable, file::ParsedFile)
    query = scopes_query_for(file.language)
    query === nothing && return table
    caps = collect_scopes(file.tree, query, file.source)
    isempty(caps.scopes) && return table
    imports = imports_query_for(file.language)
    regions = imports === nothing ? ModuleRegion[] : module_regions(file.tree, imports, file.source)
    root = root_scope(caps.scopes)
    namespaces = Set{Tuple{Int, Int}}([(root.from, root.to)])
    for r in regions
        push!(namespaces, (r.from, r.to))
    end
    units = file.index.functions
    uranges = Tuple{Int, Int}[TreeSitter.byte_range(u.node) for u in units]
    for (i, d) in enumerate(caps.defnodes)
        kind = caps.defkinds[i]
        is_symbol_kind(kind) || continue
        from, to = TreeSitter.byte_range(d)
        owner = owning_scope(caps.scopes, from, to, caps.defhoist[i])
        owner === nothing && continue
        (owner.from, owner.to) in namespaces || continue
        name = String(strip(TreeSitter.slice(file.source, d)))
        path = module_path_of(regions, from, to)
        unit = containing_unit(uranges, from, to)
        line = Int(TreeSitter.start_point(d).row) + 1
        push!(table.defs, CorpusDef(file.file, nodeid(d), name, kind, path, false, unit, line))
        push!(get!(() -> Int[], table.by_name, (file.language, path, name)), length(table.defs))
    end
    return table
end

# A reference with no in-file definition: its identity, the name it uses, and the
# function-unit index it sits in (0 at file scope). These are the references the corpus
# graph resolves across files.
struct UnboundRef
    id::NodeId
    name::String
    unit::Int
end

"""
    unbound_references(file) -> Vector{UnboundRef}

The references in `file` that resolve to no in-file definition, each tagged with its
name and containing function unit. The per-file binding resolver drops these; the
corpus graph picks them up and tries to resolve them against [`corpus_symbols`](@ref).
A file whose language ships no scopes query yields none.
"""
function unbound_references(file::ParsedFile)
    query = scopes_query_for(file.language)
    query === nothing && return UnboundRef[]
    caps = collect_scopes(file.tree, query, file.source)
    isempty(caps.scopes) && return UnboundRef[]
    assign_defs!(caps, file.source)
    units = file.index.functions
    uranges = Tuple{Int, Int}[TreeSitter.byte_range(u.node) for u in units]
    refs = UnboundRef[]
    for r in caps.refnodes
        rid = nodeid(r)
        rid in caps.defids && continue
        from, to = TreeSitter.byte_range(r)
        name = String(strip(TreeSitter.slice(file.source, r)))
        lookup_definition(caps.scopes, from, to, name) === nothing || continue
        push!(refs, UnboundRef(rid, name, containing_unit(uranges, from, to)))
    end
    return refs
end

"""
    corpus_symbols(files) -> SymbolTable

The top-level definitions across `files`, indexed by language, enclosing module path,
and name. The table a cross-file reference resolves against: each file contributes the
functions, types, macros, and consts visible at its module scope, skipping locals and
languages with no scopes query.
"""
function corpus_symbols(files::AbstractVector{ParsedFile})
    table = SymbolTable()
    for file in files
        file_symbols!(table, file)
    end
    return table
end

# How a language lets one file see another's names. `model` picks the resolver:
# `:splice` joins included files into one namespace (Julia `include`, C `#include`);
# `:import` brings named or whole-module names in (Python, JS). `resolve_target` maps a
# captured include/import string to corpus file paths; `is_exported` decides whether a
# definition is visible outside its file.
struct Linkage
    model::Symbol
    resolve_target::Function
    is_exported::Function
end

# Resolve a splice target (`include("path")`) to a corpus file: the path is relative to
# the including file's directory. Returns the one corpus path it names, or none when the
# target is outside the corpus (a stdlib or generated file).
function splice_resolve(target::AbstractString, fromfile::AbstractString, corpus::Set{String})
    rel = strip(target, ['"', '\''])
    path = normpath(joinpath(dirname(fromfile), rel))
    return path in corpus ? [path] : String[]
end

# A spliced file's top-level names join the includer's namespace; a name inside a nested
# module does not, so only file-scope definitions are visible across the splice.
splice_exported(def::CorpusDef, ::Set{String}) = isempty(def.module_path)

const LINKAGES = Dict{Symbol, Linkage}(
    :julia => Linkage(:splice, splice_resolve, splice_exported),
)

# The splice target strings an imports query tags in one file (`@include.path`), quotes
# and all, for the linkage resolver to map to corpus paths.
function include_targets(tree::TreeSitter.Tree, query::TreeSitter.Query, source::AbstractString)
    targets = String[]
    for cap in TreeSitter.each_capture(tree, query, source)
        TreeSitter.capture_name(query, cap) == "include.path" || continue
        push!(targets, String(TreeSitter.slice(source, cap.node)))
    end
    return targets
end

# Group files into shared namespaces by following splice edges: an `include` joins two
# files into one module, so a reference in either resolves to the other's names. Returns
# a file path to component-root map (union-find over the file index).
function inclusion_components(files::AbstractVector{ParsedFile}, corpus::Set{String})
    index = Dict{String, Int}(f.file => i for (i, f) in enumerate(files))
    parent = collect(1:length(files))
    for f in files
        link = get(LINKAGES, f.language, nothing)
        (link === nothing || link.model !== :splice) && continue
        query = imports_query_for(f.language)
        query === nothing && continue
        for target in include_targets(f.tree, query, f.source)
            for path in link.resolve_target(target, f.file, corpus)
                j = get(index, path, 0)
                j == 0 && continue
                parent[uf_find(parent, j)] = uf_find(parent, index[f.file])
            end
        end
    end
    roots = Dict{String, Int}()
    for f in files
        roots[f.file] = uf_find(parent, index[f.file])
    end
    return roots
end

"""
    visible_defs(files, table, corpus) -> Dict{String, Dict{String, Vector{Int}}}

For each file, the corpus definitions it can reference from another file, indexed by
name. A splice makes every file in one inclusion component share its members'
file-scope names; `is_exported` drops names a nested module keeps private. A file's own
definitions are excluded, so the map carries only cross-file candidates.
"""
function visible_defs(files::AbstractVector{ParsedFile}, table::SymbolTable, corpus::Set{String})
    roots = inclusion_components(files, corpus)
    bycomp = Dict{Int, Vector{Int}}()
    for (di, d) in enumerate(table.defs)
        root = get(roots, d.file, 0)
        root == 0 && continue
        push!(get!(() -> Int[], bycomp, root), di)
    end
    langof = Dict{String, Symbol}(f.file => f.language for f in files)
    visible = Dict{String, Dict{String, Vector{Int}}}()
    for f in files
        members = get(bycomp, roots[f.file], Int[])
        names = Dict{String, Vector{Int}}()
        link = get(LINKAGES, f.language, nothing)
        for di in members
            d = table.defs[di]
            d.file == f.file && continue
            link === nothing || link.is_exported(d, Set{String}()) || continue
            push!(get!(() -> String[], names, d.name), di)
        end
        visible[f.file] = names
    end
    return visible
end
