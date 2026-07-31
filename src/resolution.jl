# Resolving the corpus against itself. The per-file binding resolver (`bindings.jl`) leaves
# a reference unbound when its definition lives in another file. This builds the table those
# references resolve against, works out what each file can see across the boundary, matches
# every unbound reference to the definitions it names, and reads the two corpus-wide
# summaries the rules want off the result: who consumes each definition, and each file's
# public surface. `linkage.jl` holds the per-language rules it resolves through.
#
# `resolve_linkage` is the entry point, and the one value it returns is what every pass past
# a single file takes. Resolving a corpus is among the most expensive steps in a scan, so it
# happens once per scan rather than once per reader.
#
# Name-based and lexical, never typed: a reference matches the definition it lexically names,
# gated by declared visibility. The file boundary is crossed; the symbol-resolution one is
# not. A name matching several visible definitions keeps all of them rather than picking one,
# since picking would need the dispatch resolution Dendro does not do.

"""
    corpus_symbols(files) -> SymbolTable

The top-level definitions across `files`, each carrying its enclosing module path. The
table a cross-file reference resolves against: each file contributes the functions,
types, macros, and consts visible at its module scope, skipping locals and languages
with no scopes query.
"""
# Every name this fan-out touches (`SymbolTable`, `CorpusDef`, `file_symbols!`) is the
# registry's by design, so its coupling sits at the `:misplaced` band. Moving it to
# `linkage.jl` would put a corpus-wide fan-out inside the table of independent per-language
# rules, which is the split resolution and registry exist to keep.
# dendro-ignore: misplaced -- fanning `file_symbols!` over the corpus is resolution's job
function corpus_symbols(files::Vector{ParsedFile})
    table = SymbolTable()
    append!(
        table.defs,
        parallel_flatmap(i -> file_symbols!(SymbolTable(), files[i]).defs, length(files), CorpusDef),
    )
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
    CorpusReference

One cross-file reference the corpus resolved: the `file` it sits in, the reference itself,
and the `candidates`, indices into `SymbolTable.defs`, its name reaches. A name matching
several visible definitions carries all of them, since picking one would need the dispatch
resolution Dendro does not do.
"""
struct CorpusReference
    file::ParsedFile
    ref::UnboundRef
    candidates::Vector{Int}
end

"""
    unbound_references(file) -> Vector{UnboundRef}

The references in `file` that resolve to no in-file definition, each tagged with the
name it resolves under and its containing function unit. The per-file binding resolver
drops these; the corpus graph picks them up and tries to resolve them against
[`corpus_symbols`](@ref). A reference qualified by a namespace carries the qualified name
([`reference_name`](@ref)). A file whose language ships no scopes query yields none.
"""
function unbound_references(file::ParsedFile)
    caps = file.index.scope_captures
    isempty(caps.scopes) && return UnboundRef[]
    units = file.index.units
    uranges = Tuple{Int, Int}[unit_span(u) for u in units]
    access = get(MODULE_ACCESS, file.language, nothing)
    refs = UnboundRef[]
    for r in caps.refnodes
        rid = nodeid(r)
        rid in caps.defids && continue
        from, to = TreeSitter.byte_range(r)
        name = String(strip(TreeSitter.slice(file.source, r)))
        lookup_definition(caps.scopes, from, to, name) === nothing || continue
        resolved = reference_name(r, file.source, access, name)
        push!(refs, UnboundRef(rid, resolved, containing_unit(uranges, from, to)))
    end
    return refs
end

# Both readings of the corpus splice graph a resolver needs: the component root each file
# belongs to, the files an `include` chain joins into one namespace, and the module path
# each file is spliced into.
struct SpliceGraph
    components::Dict{String, Int}
    namespaces::Dict{String, Vector{String}}
end

# Follow every splice edge in the corpus. An `include` joins two files into one module, so
# a reference in either resolves to the other's names, and the file it pulls in lands in
# the namespace enclosing that `include`. Components come from a union-find over the file
# index; the namespace paths are walked down from the splice roots.
function splice_graph(files::Vector{ParsedFile}, corpus::Corpus)
    index = Dict{String, Int}(to_posix(f.file) => i for (i, f) in enumerate(files))
    edges = [Tuple{Int, Vector{String}}[] for _ in files]
    included = falses(length(files))
    parent = collect(1:length(files))
    for (i, f) in enumerate(files)
        link = get(LINKAGES, f.language, nothing)
        (link === nothing || link.model !== :splice) && continue
        query = imports_query_for(f)
        query === nothing && continue
        regions = module_regions(f.tree, query, f.source)
        for target in include_targets(f.tree, query, f.source)
            for path in link.resolve_target(target.path, f.file, corpus)::Vector{String}
                j = get(index, path, 0)
                j == 0 && continue
                push!(edges[i], (j, module_path_of(regions, target.from, target.to)))
                included[j] = true
                parent[uf_find(parent, j)] = uf_find(parent, i)
            end
        end
    end
    components = Dict{String, Int}(f.file => uf_find(parent, i) for (i, f) in enumerate(files))
    return SpliceGraph(components, splice_namespaces(files, edges, included))
end

# The module path each file is spliced into, outermost first: the namespace enclosing the
# `include` that pulled it in, accumulated down the chain from each splice root, a file
# `included` marks as reached by no other. This is the namespace a file-scope definition
# belongs to and its own per-file module path cannot record, since the `module` is
# declared in the includer, not in the file itself. A file in an include cycle with no
# root above it belongs to no namespace the corpus can name and gets no entry.
function splice_namespaces(
        files::Vector{ParsedFile}, edges::Vector{Vector{Tuple{Int, Vector{String}}}},
        included::BitVector
    )
    paths = Dict{String, Vector{String}}()
    queue = Int[]
    for i in eachindex(files)
        included[i] && continue
        paths[files[i].file] = String[]
        push!(queue, i)
    end
    head = 1
    while head <= length(queue)
        i = queue[head]
        head += 1
        for (j, site) in edges[i]
            haskey(paths, files[j].file) && continue
            paths[files[j].file] = vcat(paths[files[i].file], site)
            push!(queue, j)
        end
    end
    return paths
end

"""
    DeclaredLinkage

What the corpus declares about linkage, walked once per scan: `exports` holds each file's
export names aligned with the `files` it was built from, and `splices` the graph of include
edges joining files into one namespace. [`visible_defs`](@ref) and [`public_surface`](@ref)
are two readings of it, so one scan walks the linkage queries once rather than once per
reading.
"""
struct DeclaredLinkage
    exports::Vector{Set{String}}
    splices::SpliceGraph
end

DeclaredLinkage(files::Vector{ParsedFile}, corpus::Corpus) =
    DeclaredLinkage(corpus_exports(files), splice_graph(files, corpus))

"""
    visible_defs(files, table, corpus, declared) -> Dict{String, Dict{String, Vector{Int}}}

For each file, the corpus definitions it can reference from another file, indexed by
name. The linkage model selects how: a splice shares every file-scope name in an
inclusion component, an import brings the named definitions of a resolved module, a
package adds the same-directory types an import model resolves without an import. A
file's own definitions are excluded, and a file whose language has no linkage sees
nothing across the boundary.
"""
function visible_defs(
        files::Vector{ParsedFile}, table::SymbolTable, corpus::Corpus, declared::DeclaredLinkage
    )
    roots = declared.splices.components
    bycomp = Dict{Int, Vector{Int}}()
    defs_by_file = Dict{String, Vector{Int}}()
    defs_by_dir = Dict{String, Vector{Int}}()
    for (di, d) in enumerate(table.defs)
        root = get(roots, d.file, 0)
        root == 0 || push!(get!(() -> Int[], bycomp, root), di)
        push!(get!(() -> Int[], defs_by_file, to_posix(d.file)), di)
        push!(get!(() -> Int[], defs_by_dir, dirname(d.file)), di)
    end
    n = length(files)
    exports_by_file = Dict{String, Set{String}}(to_posix(files[i].file) => declared.exports[i] for i in 1:n)
    vi = VisibilityIndex(
        table, corpus, roots, bycomp, declared.splices.namespaces, defs_by_dir, defs_by_file, exports_by_file
    )
    entries = Vector{Dict{String, Vector{Int}}}(undef, n)
    parallel_map!(i -> file_visible(files[i], vi), entries)
    visible = Dict{String, Dict{String, Vector{Int}}}()
    for i in 1:n
        visible[files[i].file] = entries[i]
    end
    return visible
end

"""
    corpus_visibility(files, table) -> Dict{String, Dict{String, Vector{Int}}}

Each file's cross-file candidates by name: [`visible_defs`](@ref) over the corpus `files`
themselves form. A caller that needs more than the visibility, the references it admits or
the public surface beside it, resolves the whole corpus once through
[`resolve_linkage`](@ref) instead.
"""
function corpus_visibility(files::Vector{ParsedFile}, table::SymbolTable)
    corpus = Corpus(files)
    return visible_defs(files, table, corpus, DeclaredLinkage(files, corpus))
end

"""
    corpus_references(files, table) -> Vector{CorpusReference}
    corpus_references(files, visible) -> Vector{CorpusReference}

Every cross-file reference in `files` that resolves against `table`, paired with the
file it sits in and the candidate definition indices its name reaches through
[`visible_defs`](@ref). Unlike the corpus graph, this keeps a reference sitting in
top-level code (`ref.unit == 0`): the reachability pass attributes a reference to its
enclosing definition by byte range, not by unit, and a top-level reference is a root
edge. A name matching several visible definitions yields all of them.

Pass a prebuilt `visible` from [`corpus_visibility`](@ref) to share one resolution with
a caller that reads the visibility itself.
"""
corpus_references(files::Vector{ParsedFile}, table::SymbolTable) =
    corpus_references(files, corpus_visibility(files, table))

function corpus_references(files::Vector{ParsedFile}, visible::Dict{String, Dict{String, Vector{Int}}})
    return parallel_flatmap(length(files), CorpusReference) do i
        f = files[i]
        names = visible[f.file]
        acc = CorpusReference[]
        for ref in unbound_references(f)
            candidates = get(names, ref.name, nothing)
            candidates === nothing && continue
            push!(acc, CorpusReference(f, ref, candidates))
        end
        acc
    end
end

"""
    consumer_sets(references, table) -> Dict{String, Dict{Int, Set{String}}}

Per corpus file, the definitions in it that something else references and the set of files
referencing each. The audience a definition serves is who names it, so this is a reading of
the already-resolved `references`; a file's own definitions are outside its visibility map,
so every reference here crosses a file boundary. A reference matching several visible
definitions counts toward each: the match is by name, and picking one would need the
dispatch resolution Dendro never does. A reference in top-level code counts like any other,
since the question is which file consumes the definition, not which unit.

`:split_audience` scores the groups this projects into and `:hub` proposes a split along
them, so one scan reads it once.
"""
function consumer_sets(references::Vector{CorpusReference}, table::SymbolTable)
    out = Dict{String, Dict{Int, Set{String}}}()
    for reference in references
        for di in reference.candidates
            d = table.defs[di]
            defs = get!(() -> Dict{Int, Set{String}}(), out, d.file)
            push!(get!(() -> Set{String}(), defs, di), reference.file.file)
        end
    end
    return out
end

"""
    public_surface(files, declared) -> Dict{String, Set{String}}

The export names that gate each file's public definitions. For an import model the set
is the file's own [`file_exports`](@ref); for a splice model it is the union across the
file's inclusion component, so a Julia name exported from the module file counts as
public for the spliced file that defines it. A language with no linkage maps to an empty
set; its convention or modifier predicate decides publicness without consulting it.

Both readings come out of `declared`, the same [`DeclaredLinkage`](@ref) the visibility map
is built from, so a scan walks the export and include captures once.
"""
function public_surface(files::Vector{ParsedFile}, declared::DeclaredLinkage)
    own = Dict{String, Set{String}}(files[i].file => declared.exports[i] for i in eachindex(files))
    components = declared.splices.components
    by_component = Dict{Int, Set{String}}()
    for f in files
        link = get(LINKAGES, f.language, nothing)
        (link === nothing || link.model !== :splice) && continue
        union!(get!(() -> Set{String}(), by_component, components[f.file]), own[f.file])
    end
    surface = Dict{String, Set{String}}()
    for f in files
        link = get(LINKAGES, f.language, nothing)
        surface[f.file] = if link !== nothing && link.model === :splice
            get(by_component, components[f.file], Set{String}())
        else
            own[f.file]
        end
    end
    return surface
end

"""
    ResolvedLinkage

The corpus resolved against itself, the substrate every pass past a single file reads.
`corpus` is the path set it resolved against, `visible` holds each file's cross-file
candidates by name, `references` every cross-file reference those candidates admit,
`consumers` the files referencing each consumed definition, and `surface` the export names
gating each file's public definitions.

`corpus` is carried rather than rebuilt by the file graph, which needs the same path set to
map an import target to the file it names. It rides on the record instead of arriving as a
keyword because a keyword's lowering is what the sound ratchet counts, and sharing an O(n)
set build is not worth paying for in inference.

Resolving a corpus is among the most expensive steps in a scan, and six passes want the same
answer: both graphs, reachability, the audience pass, the hub proposal, and the back-edge
reference sites. So [`resolve_linkage`](@ref) resolves it once and each pass takes this
rather than resolving again. It travels through the same keyword slot the `visible` map used
to, which is why widening it costs no pass a parameter.
"""
struct ResolvedLinkage
    corpus::Corpus
    visible::Dict{String, Dict{String, Vector{Int}}}
    references::Vector{CorpusReference}
    consumers::Dict{String, Dict{Int, Set{String}}}
    surface::Dict{String, Set{String}}
end

"""
    resolve_linkage(files, table) -> ResolvedLinkage

Resolve `files` against `table` once: the corpus path set, the visibility map, the
cross-file references it admits, the per-definition consumer index, and the public surface.
Every reading comes out of one [`DeclaredLinkage`](@ref) walk and one [`visible_defs`](@ref)
pass, so a scan pays for the corpus resolution once however many passes read it.
"""
function resolve_linkage(files::Vector{ParsedFile}, table::SymbolTable)
    corpus = Corpus(files)
    declared = DeclaredLinkage(files, corpus)
    visible = visible_defs(files, table, corpus, declared)
    references = corpus_references(files, visible)
    return ResolvedLinkage(
        corpus, visible, references, consumer_sets(references, table), public_surface(files, declared)
    )
end
