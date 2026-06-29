# Corpus-wide symbol resolution. The per-file binding resolver (`bindings.jl`) leaves
# a reference unbound when its definition lives in another file. This builds the table
# those references resolve against: every top-level definition across the corpus, each
# carrying the enclosing module path that scopes a name match. Name-based and lexical,
# never typed: it records what a name is declared as, not what a call dispatches to. The
# file boundary is crossed; the symbol-resolution one is not.
#
# This file is a registry of per-language resolvers: one independent `*_resolve` and
# visibility rule per language, with nothing to connect them, so it reads as low
# cohesion by design.
# dendro-ignore-file: low_cohesion

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
# first), the function-unit index it belongs to (0 for a type or const outside any
# unit), and its source line.
struct CorpusDef
    file::String
    id::NodeId
    name::String
    kind::Symbol
    module_path::Vector{String}
    unit::Int
    line::Int
end

# Every top-level definition across the corpus. A cross-file reference resolves against
# it by name, gated by what its file can see; the module path each def carries scopes a
# match to the namespace a reference can reach.
struct SymbolTable
    defs::Vector{CorpusDef}
end
SymbolTable() = SymbolTable(CorpusDef[])

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
        push!(table.defs, CorpusDef(file.file, nodeid(d), name, kind, path, unit, line))
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

The top-level definitions across `files`, each carrying its enclosing module path. The
table a cross-file reference resolves against: each file contributes the functions,
types, macros, and consts visible at its module scope, skipping locals and languages
with no scopes query.
"""
function corpus_symbols(files::Vector{ParsedFile})
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
# Corpus resolution works in POSIX-separated path space: the corpus key set and the paths
# the resolvers build are compared with `/`, so a match never depends on the host OS
# separator that `joinpath`/`normpath` would emit. Display paths keep their original form.
to_posix(path::AbstractString) = replace(path, '\\' => '/')

# Join and normalize a relative path, then force `/` separators, so a constructed candidate
# matches a POSIX-normalized corpus key on any OS.
corpus_join(parts::AbstractString...) = to_posix(normpath(joinpath(parts...)))

# target is outside the corpus (a stdlib or generated file).
function splice_resolve(target::AbstractString, fromfile::AbstractString, corpus::Set{String})
    rel = strip(target, ['"', '\''])
    path = corpus_join(dirname(fromfile), rel)
    return path in corpus ? [path] : String[]
end

# A spliced file's top-level names join the includer's namespace; a name inside a nested
# module does not, so only file-scope definitions are visible across the splice.
splice_exported(def::CorpusDef, ::Set{String}) = isempty(def.module_path)

# Resolve a Python module reference to corpus files. A relative import (`.util`,
# `..pkg.mod`) resolves against the importing file's directory, one level up per leading
# dot; an absolute import (`a.b`) matches any corpus path ending in that module path.
# Each names a module file or a package's `__init__.py`.
function python_resolve(target::AbstractString, fromfile::AbstractString, corpus::Set{String})
    level = 0
    while level < length(target) && target[level + 1] == '.'
        level += 1
    end
    parts = split(target[(level + 1):end], '.'; keepempty = false)
    found = String[]
    if level == 0
        rel = join(parts, '/')
        append!(found, suffix_match(corpus, (rel * ".py", rel * "/__init__.py")))
    else
        base = dirname(fromfile)
        for _ in 1:(level - 1)
            base = dirname(base)
        end
        rel = join(parts, '/')
        initpkg = isempty(rel) ? "__init__.py" : rel * "/__init__.py"
        for suffix in (rel * ".py", initpkg)
            path = corpus_join(base, suffix)
            path in corpus && push!(found, path)
        end
    end
    return unique(found)
end

# Python has no export marker: an imported top-level name is visible, the import list
# does the gating.
import_exported(::CorpusDef, ::Set{String}) = true

# Resolve a JavaScript module specifier to corpus files. Only a relative specifier
# (`./mod`, `../lib/mod`) names a corpus file; a bare specifier is a package. The path
# resolves against the importing file's directory, trying each module extension and an
# `index` file in a directory.
function js_resolve(target::AbstractString, fromfile::AbstractString, corpus::Set{String})
    spec = strip(target, ['"', '\'', '`'])
    startswith(spec, ".") || return String[]
    base = corpus_join(dirname(fromfile), spec)
    found = String[]
    base in corpus && push!(found, base)
    for ext in (".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx")
        (base * ext) in corpus && push!(found, base * ext)
        index = corpus_join(base, "index" * ext)
        index in corpus && push!(found, index)
    end
    return unique(found)
end

# JavaScript exports by name: only a name the module marks `export` is visible to an
# importer, so the def's file must list it.
js_exported(def::CorpusDef, exports::Set{String}) = def.name in exports

# Ruby `require_relative` names a file without its `.rb` extension, relative to the
# requiring file. The required file's top-level definitions splice into scope.
function ruby_resolve(target::AbstractString, fromfile::AbstractString, corpus::Set{String})
    rel = strip(target, ['"', '\''])
    endswith(rel, ".rb") || (rel = rel * ".rb")
    path = corpus_join(dirname(fromfile), rel)
    return path in corpus ? [path] : String[]
end

# Corpus files whose path ends in one of `options`, the suffix-match the import-model
# languages with absolute module paths share (Rust, Java, PHP), where a build system,
# not the source, fixes the real root.
function suffix_match(corpus::Set{String}, options::Tuple{Vararg{AbstractString}})
    found = String[]
    for option in options, path in corpus
        (path == option || endswith(path, "/" * option)) && push!(found, path)
    end
    return unique(found)
end

# Rust `use a::b::c` names module `a::b` in @import.from, item `c` in @import.name, so
# the path is already the module: drop only the path roots, resolving `a/b.rs` or
# `a/b/mod.rs`.
function rust_resolve(target::AbstractString, ::AbstractString, corpus::Set{String})
    parts = [p for p in split(target, "::"; keepempty = false) if !(p in ("crate", "self", "super"))]
    isempty(parts) && return String[]
    rel = join(parts, '/')
    return suffix_match(corpus, (rel * ".rs", rel * "/mod.rs"))
end

# Java `import com.foo.Bar` names class `Bar` in file `com/foo/Bar.java`: the qualified
# name is the file path, one public class per file.
function java_resolve(target::AbstractString, ::AbstractString, corpus::Set{String})
    rel = replace(target, "." => "/")
    return suffix_match(corpus, (rel * ".java",))
end

# PHP `use App\Foo` names `Foo` in file `App/Foo.php`, the PSR-4 convention mapping a
# namespace to a directory.
function php_resolve(target::AbstractString, ::AbstractString, corpus::Set{String})
    rel = replace(strip(target, '\\'), "\\" => "/")
    return suffix_match(corpus, (rel * ".php",))
end

# Go and similar package-by-directory models do not resolve a target string; visibility
# is by shared directory.
no_resolve(::AbstractString, ::AbstractString, ::Set{String}) = String[]

const LINKAGES = Dict{Symbol, Linkage}(
    :julia => Linkage(:splice, splice_resolve, splice_exported),
    :c => Linkage(:splice, splice_resolve, splice_exported),
    :cpp => Linkage(:splice, splice_resolve, splice_exported),
    :ruby => Linkage(:splice, ruby_resolve, splice_exported),
    :go => Linkage(:directory, no_resolve, import_exported),
    :python => Linkage(:import, python_resolve, import_exported),
    :javascript => Linkage(:import, js_resolve, js_exported),
    :typescript => Linkage(:import, js_resolve, js_exported),
    :rust => Linkage(:import, rust_resolve, import_exported),
    :java => Linkage(:import, java_resolve, import_exported),
    :php => Linkage(:import, php_resolve, import_exported),
)

# The names a file marks for export, from the `@export` captures of its linkage query.
# Empty for a language with no export marker, where every top-level name is importable.
function file_exports(file::ParsedFile)
    query = imports_query_for(file.language)
    query === nothing && return Set{String}()
    exports = Set{String}()
    for cap in TreeSitter.each_capture(file.tree, query, file.source)
        TreeSitter.capture_name(query, cap) == "export" || continue
        push!(exports, String(strip(TreeSitter.slice(file.source, cap.node))))
    end
    return exports
end

# The `from <module> import <names>` statements in one file, each as the module string
# and the set of names it brings into scope. A name is paired to the statement whose
# byte range contains it, the same geometric test the module regions use.
function file_imports(file::ParsedFile)
    query = imports_query_for(file.language)
    query === nothing && return Tuple{String, Set{String}}[]
    regions = Tuple{Int, Int}[]
    froms = TreeSitter.Node[]
    names = TreeSitter.Node[]
    for cap in TreeSitter.each_capture(file.tree, query, file.source)
        name = TreeSitter.capture_name(query, cap)
        name == "import" && push!(regions, TreeSitter.byte_range(cap.node))
        name == "import.from" && push!(froms, cap.node)
        name == "import.name" && push!(names, cap.node)
    end
    imports = Tuple{String, Set{String}}[]
    for (rf, rt) in regions
        module_name = ""
        for node in froms
            nf, nt = TreeSitter.byte_range(node)
            if rf <= nf && nt <= rt
                module_name = String(strip(TreeSitter.slice(file.source, node)))
                break
            end
        end
        isempty(module_name) && continue
        imported = Set{String}()
        for node in names
            nf, nt = TreeSitter.byte_range(node)
            (rf <= nf && nt <= rt) && push!(imported, String(strip(TreeSitter.slice(file.source, node))))
        end
        push!(imports, (module_name, imported))
    end
    return imports
end

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
function inclusion_components(files::Vector{ParsedFile}, corpus::Set{String})
    index = Dict{String, Int}(to_posix(f.file) => i for (i, f) in enumerate(files))
    parent = collect(1:length(files))
    for (i, f) in enumerate(files)
        link = get(LINKAGES, f.language, nothing)
        (link === nothing || link.model !== :splice) && continue
        query = imports_query_for(f.language)
        query === nothing && continue
        for target in include_targets(f.tree, query, f.source)
            for path in link.resolve_target(target, f.file, corpus)::Vector{String}
                j = get(index, path, 0)
                j == 0 && continue
                parent[uf_find(parent, j)] = uf_find(parent, i)
            end
        end
    end
    roots = Dict{String, Int}()
    for (i, f) in enumerate(files)
        roots[f.file] = uf_find(parent, i)
    end
    return roots
end

# The cross-file names a file sees from a set of candidate definitions: every member's
# name, its own file's excluded. Shared by the splice model, whose members are an
# inclusion component, and the directory model, whose members are a package directory.
function member_visible(f::ParsedFile, table::SymbolTable, link::Linkage, members::Vector{Int})
    names = Dict{String, Vector{Int}}()
    for di in members
        d = table.defs[di]
        d.file == f.file && continue
        link.is_exported(d, Set{String}())::Bool || continue
        push!(get!(() -> String[], names, d.name), di)
    end
    return names
end

# The cross-file names an import file sees: for each import statement, the definitions
# in the resolved module file whose name the import brings in and the module exports.
function import_visible(
        f::ParsedFile, table::SymbolTable, link::Linkage, corpus::Set{String},
        defs_by_file::Dict{String, Vector{Int}}, exports_by_file::Dict{String, Set{String}}
    )
    names = Dict{String, Vector{Int}}()
    for (module_name, imported) in file_imports(f)
        for path in link.resolve_target(module_name, f.file, corpus)::Vector{String}
            exports = get(() -> Set{String}(), exports_by_file, path)
            for di in get(defs_by_file, path, Int[])
                d = table.defs[di]
                d.file == f.file && continue
                link.is_exported(d, exports)::Bool || continue
                (isempty(imported) || d.name in imported) || continue
                push!(get!(() -> String[], names, d.name), di)
            end
        end
    end
    return names
end

"""
    visible_defs(files, table, corpus) -> Dict{String, Dict{String, Vector{Int}}}

For each file, the corpus definitions it can reference from another file, indexed by
name. The linkage model selects how: a splice shares every file-scope name in an
inclusion component, an import brings the named definitions of a resolved module. A
file's own definitions are excluded, and a file whose language has no linkage sees
nothing across the boundary.
"""
function visible_defs(files::Vector{ParsedFile}, table::SymbolTable, corpus::Set{String})
    roots = inclusion_components(files, corpus)
    bycomp = Dict{Int, Vector{Int}}()
    defs_by_file = Dict{String, Vector{Int}}()
    defs_by_dir = Dict{String, Vector{Int}}()
    for (di, d) in enumerate(table.defs)
        root = get(roots, d.file, 0)
        root == 0 || push!(get!(() -> Int[], bycomp, root), di)
        push!(get!(() -> Int[], defs_by_file, to_posix(d.file)), di)
        push!(get!(() -> Int[], defs_by_dir, dirname(d.file)), di)
    end
    exports_by_file = Dict{String, Set{String}}(to_posix(f.file) => file_exports(f) for f in files)
    visible = Dict{String, Dict{String, Vector{Int}}}()
    for f in files
        link = get(LINKAGES, f.language, nothing)
        visible[f.file] = if link === nothing
            Dict{String, Vector{Int}}()
        elseif link.model === :splice
            member_visible(f, table, link, get(bycomp, roots[f.file], Int[]))
        elseif link.model === :directory
            member_visible(f, table, link, get(defs_by_dir, dirname(f.file), Int[]))
        else
            import_visible(f, table, link, corpus, defs_by_file, exports_by_file)
        end
    end
    return visible
end
