# How a language lets one file see another's names. This is the registry side of cross-file
# resolution: one independent `*_resolve`, export rule, and visibility rule per language,
# the readings of a language's linkage query those rules are written over, and what each
# linkage model makes visible for one file. What resolves a whole corpus against this is
# `resolution.jl`.
#
# Name-based and lexical, never typed: a rule here records what a name is declared as and
# where a declared target points, not what a call dispatches to.
#
# One independent rule per language, with nothing to connect them, so it reads as low
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
# unit), its source line, its declared visibility (`:public`/`:private`/`:unknown`,
# read from a per-def modifier where a language has one, `:unknown` otherwise), and
# whether it is an external-entry root: a definition a wrapping construct the analyzer
# cannot expand consumes (a macro, decorator, annotation, attribute), so reachability
# roots the dead-code search from it rather than judging it dead.
#
# The record lives here rather than beside the pass that builds it, because every
# per-language export and visibility rule below is written over one.
struct CorpusDef
    file::String
    id::NodeId
    name::String
    kind::Symbol
    module_path::Vector{String}
    unit::Int
    line::Int
    visibility::Symbol
    external_root::Bool
end

# Every top-level definition across the corpus. A cross-file reference resolves against
# it by name, gated by what its file can see; the module path each def carries scopes a
# match to the namespace a reference can reach. `corpus_symbols` (`resolution.jl`) builds it.
struct SymbolTable
    defs::Vector{CorpusDef}
end
SymbolTable() = SymbolTable(CorpusDef[])

# Definition kinds that name a top-level, corpus-visible symbol. Locals bind inside a
# function scope and never reach another file, so they are not indexed.
const SYMBOL_KINDS = (:function, :struct, :macro, :class, :const)
is_symbol_kind(kind::Symbol) = kind in SYMBOL_KINDS

# Definition kinds that name a type, the symbols a same-package reference resolves to.
is_type_kind(kind::Symbol) = kind === :struct || kind === :class

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

# The visibility a definition declares, read through the language's `Linkage.visibility`
# hook: `:public`/`:private`, or `:unknown` where the language marks nothing per definition.
# `modifier_public` treats `:unknown` as public, the safe direction.
#
# Each hook reads only a marker whose private definition cannot be reached cross-file by
# name: a Rust non-`pub` item is module-private, a C/C++ `static` function is file-local, a
# Ruby, Java, or PHP `private` method is same-class, so an unreferenced one is genuinely
# dead. A package-private Java or PHP member is left public on purpose: it is reached
# same-package without an import the resolver sees, so flagging it would be a false
# positive.
function def_visibility(file::ParsedFile, defnode::TreeSitter.Node)
    link = get(LINKAGES, file.language, nothing)
    link === nothing && return :unknown
    return link.visibility(file, defnode)::Symbol
end

# A language that marks no per-definition visibility: every symbol is `:unknown`, read as
# public. Its public surface is the export list or naming convention, not a modifier.
no_visibility(::ParsedFile, ::TreeSitter.Node) = :unknown

# Java visibility from a `modifiers` child of the declaration. A class is public only when
# marked `public`; a package-private one is private, since the `:package` linkage resolves
# its same-package references, so an unreferenced one is dead. A method is private only
# when marked `private`, reached within its own file; a package-private method stays public,
# reached same-package through a receiver the resolver does not follow.
function java_visibility(::ParsedFile, defnode::TreeSitter.Node)
    decl = TreeSitter.parent(defnode)
    TreeSitter.is_null(decl) && return :unknown
    kind = TreeSitter.node_type(decl)
    kind == "class_declaration" && return has_modifier(decl, "public") ? :public : :private
    kind == "method_declaration" && return has_modifier(decl, "private") ? :private : :public
    return :public
end

# True when a declaration's `modifiers` child holds a keyword node of type `keyword`.
function has_modifier(decl::TreeSitter.Node, keyword::String)
    for c in TreeSitter.children(decl)
        TreeSitter.node_type(c) == "modifiers" || continue
        for m in TreeSitter.children(c)
            TreeSitter.node_type(m) == keyword && return true
        end
    end
    return false
end

# PHP marks a method `private` with a `visibility_modifier`. Only `private` is private: a
# protected or unmarked method, a top-level function, and a class stay public, the same
# same-file reasoning as Java.
function php_visibility(file::ParsedFile, defnode::TreeSitter.Node)
    decl = TreeSitter.parent(defnode)
    TreeSitter.is_null(decl) && return :unknown
    TreeSitter.node_type(decl) == "method_declaration" || return :public
    for c in TreeSitter.children(decl)
        TreeSitter.node_type(c) == "visibility_modifier" || continue
        return occursin("private", TreeSitter.slice(file.source, c)) ? :private : :public
    end
    return :public
end

# Rust marks a public item with a `visibility_modifier` (`pub`, `pub(crate)`) child on the
# declaration, the captured name's parent. Its absence is private to the module, so an
# unreferenced one is unreachable from anywhere.
function rust_visibility(::ParsedFile, defnode::TreeSitter.Node)
    decl = TreeSitter.parent(defnode)
    TreeSitter.is_null(decl) && return :unknown
    for c in TreeSitter.children(decl)
        TreeSitter.node_type(c) == "visibility_modifier" && return :public
    end
    return :private
end

# A C or C++ free function with a `static` storage class has internal linkage, visible
# only in its own file, so an unreferenced one is dead. Any other definition (an extern
# function, a type) is public.
function static_visibility(file::ParsedFile, defnode::TreeSitter.Node)
    fdef = ancestor_of_type(defnode, "function_definition")
    fdef === nothing && return :public
    for c in TreeSitter.children(fdef)
        TreeSitter.node_type(c) == "storage_class_specifier" &&
            occursin("static", TreeSitter.slice(file.source, c)) && return :private
    end
    return :public
end

# Ruby methods are public until a bare `private` or `protected` statement in the class
# body toggles subsequent ones; `public` toggles back. A top-level method (in `program`,
# not a class body) is public. The toggle is a bare identifier statement, told apart from
# a `private :sym` call, which parses as a call node, not an identifier.
function ruby_visibility(file::ParsedFile, defnode::TreeSitter.Node)
    method = TreeSitter.parent(defnode)
    TreeSitter.is_null(method) && return :unknown
    body = TreeSitter.parent(method)
    (!TreeSitter.is_null(body) && TreeSitter.node_type(body) == "body_statement") || return :public
    current = :public
    target = nodeid(method)
    for c in TreeSitter.children(body)
        if TreeSitter.node_type(c) == "identifier"
            word = strip(TreeSitter.slice(file.source, c))
            (word == "private" || word == "protected") && (current = :private)
            word == "public" && (current = :public)
        elseif nodeid(c) == target
            return current
        end
    end
    return current
end

# The nearest ancestor of `node` whose type is `kind`, or `nothing`.
function ancestor_of_type(node::TreeSitter.Node, kind::String)
    n = TreeSitter.parent(node)
    while !TreeSitter.is_null(n)
        TreeSitter.node_type(n) == kind && return n
        n = TreeSitter.parent(n)
    end
    return nothing
end

# How a language writes a reference into a namespace, for the languages whose splice
# carries namespaces. A definition inside a Julia `module` never joins the includer's
# namespace, so nothing reaches it by bare name: a caller writes `Mod.name`. The resolver
# reads both sides of that through this record, keying such a definition by its qualified
# name and a reference by the qualifier it carries. `access` is the node type of a
# qualified access, `separator` what joins the namespace to the name.
struct ModuleAccess
    access::String
    separator::String
end

# The languages that reach a namespaced definition by qualifying it. Only Julia so far:
# C and C++ splice too, but their `namespace` access is a different node type and their
# nested definitions are rarer, so nothing is claimed for them until it is tested.
const MODULE_ACCESS = Dict{Symbol, ModuleAccess}(
    :julia => ModuleAccess("field_expression", "."),
)

# The namespace a qualified access names directly: the innermost component of its
# qualifier, `Inner` in `Outer.Inner.f`. A longer qualifier is itself an access node, so
# its own last child holds that component. Only the innermost is read, because a
# definition's module path is per-file: the outer modules a reference walks through can
# be declared in another file, which the path never sees.
function namespace_node(access_node::TreeSitter.Node, access::ModuleAccess)
    qualifier = first(TreeSitter.children(access_node))
    TreeSitter.node_type(qualifier) == access.access || return qualifier
    return last(TreeSitter.children(qualifier))
end

"""
    reference_name(node, source, access, name) -> String

The name `node` resolves under across the file boundary. A reference qualified by a
namespace (`Mod.f`) names a definition inside that namespace, so it resolves under the
qualified form; a bare reference resolves under its own name. This is also what keeps a
field read (`row.total`) from resolving as a bare `total`: the two are the same syntax, so
reading both as qualified names is the honest lexical answer, and a value's field matches
no namespace.
"""
function reference_name(
        node::TreeSitter.Node, source::AbstractString,
        access::Union{ModuleAccess, Nothing}, name::String
    )
    access === nothing && return name
    parent = TreeSitter.parent(node)
    TreeSitter.is_null(parent) && return name
    TreeSitter.node_type(parent) == access.access || return name
    kids = TreeSitter.children(parent)
    # Only the name side takes the qualified form. The qualifier sits left of the
    # separator, and reading it as qualified too would make `Mod` in `Mod.f` resolve
    # under `Mod.f` as well.
    length(kids) >= 2 && nodeid(last(kids)) == nodeid(node) || return name
    namespace = strip(TreeSitter.slice(source, namespace_node(parent, access)))
    return string(namespace, access.separator, name)
end

# How a language lets one file see another's names. `model` picks the resolver:
# `:splice` joins included files into one namespace (Julia `include`, C `#include`);
# `:import` brings named or whole-module names in (Python, JS); `:directory` shares a
# package directory's names (Go); `:package` adds the same-directory types an import model
# resolves without an import (Java). `resolve_target` maps a captured include/import string
# to corpus file paths; `is_exported` decides whether a definition is visible outside its
# file; `is_public` decides whether it is part of the corpus's public API, the surface
# reachability roots a dead-code search from; `visibility` reads a definition's declared
# modifier (`:public`/`:private`/`:unknown`), the input `is_public` consults for a language
# whose API surface is a per-definition keyword rather than an export list. Visibility to
# another file and membership of the public API are different questions: a Julia name is
# visible across an `include` splice without being exported, so `:unreferenced` reads
# `is_public`, not `is_exported`. `external_root(def_node, source)` decides whether a
# definition is consumed by a wrapping construct the analyzer cannot expand (a macro,
# decorator, annotation, attribute), a second source of reachability roots alongside
# `is_public`; a language without such a construct uses `no_external_root`.
#
# The callables stay abstractly typed, so each is a pointer load and each call through one
# is a dynamic dispatch. A type parameter per callable would make every language's linkage a
# distinct type, and `LINKAGES` is a `Dict{Symbol, Linkage}` resolved by language at run
# time, which needs one. The dispatch is paid once per file per question, never per node.
struct Linkage
    model::Symbol
    resolve_target::Function    # dendro-ignore: abstract_field
    is_exported::Function       # dendro-ignore: abstract_field
    is_public::Function         # dendro-ignore: abstract_field
    visibility::Function        # dendro-ignore: abstract_field
    external_root::Function     # dendro-ignore: abstract_field
end
Linkage(model, resolve_target, is_exported, is_public, visibility) =
    Linkage(model, resolve_target, is_exported, is_public, visibility, no_external_root)

# Resolution works in POSIX-separated path space: the corpus key set and the paths the
# resolvers build are compared with `/`, so a match never depends on the host OS
# separator that `joinpath`/`normpath` would emit. Display paths keep their original form.
to_posix(path::AbstractString) = replace(path, '\\' => '/')

# Join and normalize a relative path, then force `/` separators, so a constructed candidate
# matches a POSIX-normalized corpus key on any OS.
corpus_join(parts::AbstractString...) = to_posix(normpath(joinpath(parts...)))

# The final `/`-separated component of a POSIX path.
posix_basename(path::String) = (i = findlast('/', path); i === nothing ? path : path[nextind(path, i):end])

# The corpus path set paired with a basename index. The splice and relative-path
# resolvers test membership directly; the absolute-path resolvers (Rust, Java, PHP)
# match a path suffix, which the index turns from a full-corpus scan into a lookup
# keyed by the last path component.
struct Corpus
    paths::Set{String}
    by_basename::Dict{String, Vector{String}}
end
function Corpus(paths::Set{String})
    by_basename = Dict{String, Vector{String}}()
    for p in paths
        push!(get!(() -> String[], by_basename, posix_basename(p)), p)
    end
    return Corpus(paths, by_basename)
end

# The corpus a parsed file set forms, the shape every pass that resolves linkage needs.
# Paths are normalised to POSIX separators here, since the resolvers build their targets
# that way whatever the host uses, and a caller that spells this out is one `to_posix` away
# from a set that matches nothing on Windows.
Corpus(files::Vector{ParsedFile}) = Corpus(Set{String}(to_posix(f.file) for f in files))

Base.in(path::AbstractString, corpus::Corpus) = path in corpus.paths

# Resolve a splice target (`include("path")`) to a corpus file: the path is relative to
# the including file's directory. Returns the one corpus path it names, or none when the
# target is outside the corpus (a stdlib or generated file).
function splice_resolve(target::AbstractString, fromfile::AbstractString, corpus::Corpus)
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
function python_resolve(target::AbstractString, fromfile::AbstractString, corpus::Corpus)
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

# The extensions a corpus file written in one of the two ECMAScript languages carries, the
# forms a resolved module path is tried under.
const JS_SOURCE_EXTENSIONS = (".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx")

# The extensions a module specifier names a compiled module under. TypeScript's ESM output
# convention has the specifier name the emitted `.js` file while the source on disk is
# `.ts`, so a specifier ending this way is also tried with the extension dropped.
const JS_OUTPUT_EXTENSIONS = (".js", ".jsx", ".mjs", ".cjs")

# Resolve a JavaScript or TypeScript module specifier to corpus files. Only a relative
# specifier (`./mod`, `../lib/mod`) names a corpus file; a bare specifier is a package. The
# path resolves against the importing file's directory, tried as written, under each module
# extension, and, where the specifier names a compiled module, again with that extension
# dropped: `./a.js` in a TypeScript corpus names `a.ts`, and without that reading a corpus
# following the convention resolves nothing across the file boundary. A specifier that
# matches under both forms resolves to both, the same split a name matching several
# definitions already takes.
function js_resolve(target::AbstractString, fromfile::AbstractString, corpus::Corpus)
    spec = strip(target, ['"', '\'', '`'])
    startswith(spec, ".") || return String[]
    base = corpus_join(dirname(fromfile), spec)
    found = String[]
    base in corpus && push!(found, base)
    js_candidates!(found, base, corpus)
    for ext in JS_OUTPUT_EXTENSIONS
        endswith(base, ext) || continue
        js_candidates!(found, chopsuffix(base, ext), corpus)
        break
    end
    return unique(found)
end

# The corpus files a resolved module path may name: the path under each module extension,
# and a directory's `index` file under each.
function js_candidates!(found::Vector{String}, base::AbstractString, corpus::Corpus)
    for ext in JS_SOURCE_EXTENSIONS
        (base * ext) in corpus && push!(found, base * ext)
        index = corpus_join(base, "index" * ext)
        index in corpus && push!(found, index)
    end
    return found
end

# JavaScript exports by name: only a name the module marks `export` is visible to an
# importer, so the def's file must list it.
js_exported(def::CorpusDef, exports::Set{String}) = def.name in exports

# Ruby `require_relative` names a file without its `.rb` extension, relative to the
# requiring file. The required file's top-level definitions splice into scope.
function ruby_resolve(target::AbstractString, fromfile::AbstractString, corpus::Corpus)
    rel = strip(target, ['"', '\''])
    endswith(rel, ".rb") || (rel = rel * ".rb")
    path = corpus_join(dirname(fromfile), rel)
    return path in corpus ? [path] : String[]
end

# Corpus files whose path ends in one of `options`, the suffix-match the import-model
# languages with absolute module paths share (Rust, Java, PHP), where a build system,
# not the source, fixes the real root. The basename index narrows the scan to paths
# sharing an option's last component before the full suffix test.
function suffix_match(corpus::Corpus, options::Tuple{Vararg{String}})
    found = String[]
    for option in options
        cands = get(corpus.by_basename, posix_basename(option), nothing)
        cands === nothing && continue
        for path in cands
            (path == option || endswith(path, "/" * option)) && push!(found, path)
        end
    end
    return unique(found)
end

# Rust `use a::b::c` names module `a::b` in @import.from, item `c` in @import.name, so
# the path is already the module: drop only the path roots, resolving `a/b.rs` or
# `a/b/mod.rs`.
function rust_resolve(target::AbstractString, ::AbstractString, corpus::Corpus)
    parts = [p for p in split(target, "::"; keepempty = false) if !(p in ("crate", "self", "super"))]
    isempty(parts) && return String[]
    rel = join(parts, '/')
    return suffix_match(corpus, (rel * ".rs", rel * "/mod.rs"))
end

# Java `import com.foo.Bar` names class `Bar` in file `com/foo/Bar.java`: the qualified
# name is the file path, one public class per file.
function java_resolve(target::String, ::AbstractString, corpus::Corpus)
    rel = replace(target, "." => "/")
    return suffix_match(corpus, (rel * ".java",))
end

# PHP `use App\Foo` names `Foo` in file `App/Foo.php`, the PSR-4 convention mapping a
# namespace to a directory.
function php_resolve(target::String, ::AbstractString, corpus::Corpus)
    rel = replace(strip(target, '\\'), "\\" => "/")
    return suffix_match(corpus, (rel * ".php",))
end

# Go and similar package-by-directory models do not resolve a target string; visibility
# is by shared directory.
no_resolve(::AbstractString, ::AbstractString, ::Corpus) = String[]

# A definition is public when its file's export list names it, the surface for a
# language that marks its API by name (Julia `export`/`public`, a JS/TS `export`). The
# export set is the file's own for an import model, the inclusion component's for a
# splice, so a Julia name exported from the module file counts as public for the spliced
# file that defines it. The body coincides with `js_exported`, a distinct visibility rule.
# dendro-ignore: duplicate
export_public(def::CorpusDef, exports::Set{String}) = def.name in exports

# A Python definition is public unless its name leads with an underscore, the
# convention that marks a module-private name.
underscore_public(def::CorpusDef, ::Set{String}) = !startswith(def.name, "_")

# A Go definition is exported, and so public, when its name starts with an uppercase
# letter, the language's only visibility rule.
capitalized_public(def::CorpusDef, ::Set{String}) = !isempty(def.name) && isuppercase(first(def.name))

# A definition is public unless its declared visibility marks it private, the surface for
# a language that marks visibility per definition (Rust non-`pub`, a `static` C/C++
# function, a `private` Ruby/Java/PHP method). An `:unknown` visibility reads as public,
# the safe direction, so `:unreferenced` never fires on a guess.
modifier_public(def::CorpusDef, ::Set{String}) = def.visibility !== :private

# A language with no wrapping construct that consumes a definition never roots this way.
no_external_root(::TreeSitter.Node, ::AbstractString) = false

# Base and stdlib macros that wrap an ordinary definition without handing it to external
# machinery: they annotate code the reachability pass should still judge, so they do not
# root. Anything else wrapping a definition is assumed to consume it, since a route, test,
# or component macro is user-defined and open-ended; that is the safe direction, keeping
# `:unreferenced` from firing on a live registered entry point.
const JULIA_TRANSPARENT_MACROS = Set{String}(
    [
        "@inline", "@noinline", "@generated", "@propagate_inbounds", "@assume_effects",
        "@doc", "@eval", "@static", "@kwdef", "@enum",
    ]
)

# The macro name of a `macrocall_expression`, its first child (`@GET`, `@inline`), with the
# leading `@` kept so it matches `JULIA_TRANSPARENT_MACROS`.
macrocall_name(node::TreeSitter.Node, source::AbstractString) =
    String(strip(TreeSitter.slice(source, TreeSitter.child(node, 1))))

# A Julia definition roots when a macro consumes it directly: walking out from the name
# node reaches a `macrocall_expression` without crossing a body scope (`block`/
# `compound_statement`), so `@GET function h(req) ... end` roots `h` while a helper nested
# in `@testitem begin ... end` does not. A transparent wrapper does not root.
function julia_external_root(node::TreeSitter.Node, source::AbstractString)
    n = TreeSitter.parent(node)
    while !TreeSitter.is_null(n)
        t = TreeSitter.node_type(n)
        (t == "block" || t == "compound_statement") && return false
        t == "macrocall_expression" &&
            return !(macrocall_name(n, source) in JULIA_TRANSPARENT_MACROS)
        n = TreeSitter.parent(n)
    end
    return false
end

const LINKAGES = Dict{Symbol, Linkage}(
    :julia => Linkage(:splice, splice_resolve, splice_exported, export_public, no_visibility, julia_external_root),
    :c => Linkage(:splice, splice_resolve, splice_exported, modifier_public, static_visibility),
    :cpp => Linkage(:splice, splice_resolve, splice_exported, modifier_public, static_visibility),
    :ruby => Linkage(:splice, ruby_resolve, splice_exported, modifier_public, ruby_visibility),
    :go => Linkage(:directory, no_resolve, import_exported, capitalized_public, no_visibility),
    :python => Linkage(:import, python_resolve, import_exported, underscore_public, no_visibility),
    :javascript => Linkage(:import, js_resolve, js_exported, export_public, no_visibility),
    :typescript => Linkage(:import, js_resolve, js_exported, export_public, no_visibility),
    :rust => Linkage(:import, rust_resolve, import_exported, modifier_public, rust_visibility),
    :java => Linkage(:package, java_resolve, import_exported, modifier_public, java_visibility),
    :php => Linkage(:import, php_resolve, import_exported, modifier_public, php_visibility),
)

# The names a file marks for export, from the `@export` captures of its linkage query.
# Empty for a language with no export marker, where every top-level name is importable.
function file_exports(file::ParsedFile)
    query = imports_query_for(file)
    query === nothing && return Set{String}()
    exports = Set{String}()
    for cap in TreeSitter.each_capture(file.tree, query, file.source)
        TreeSitter.capture_name(query, cap) == "export" || continue
        push!(exports, String(strip(TreeSitter.slice(file.source, cap.node))))
    end
    return exports
end

# Every file's export set, computed per file in parallel, aligned with `files`. Shared by
# the visibility and public-surface passes, which key it differently.
function corpus_exports(files::Vector{ParsedFile})
    exps = Vector{Set{String}}(undef, length(files))
    parallel_map!(i -> file_exports(files[i]), exps)
    return exps
end

# One `from <module> import <names>` statement: the module string its `@import.from` child
# names, the names it brings into scope (empty for a whole-module import), and the 1-based
# line it sits on, which is where a finding about the dependency it admits points.
struct ImportStatement
    module_name::String
    names::Set{String}
    line::Int
end

# The import statements in one file. A `@import.from` module and each `@import.name` is
# paired to the statement whose byte range contains it, the same geometric test the module
# regions use. A statement whose module string is missing declares nothing and is dropped.
function file_imports(file::ParsedFile)
    query = imports_query_for(file)
    query === nothing && return ImportStatement[]
    regions = Tuple{Int, Int, Int}[]
    froms = TreeSitter.Node[]
    names = TreeSitter.Node[]
    for cap in TreeSitter.each_capture(file.tree, query, file.source)
        name = TreeSitter.capture_name(query, cap)
        name == "import" && push!(regions, (TreeSitter.byte_range(cap.node)..., line_of(cap.node)))
        name == "import.from" && push!(froms, cap.node)
        name == "import.name" && push!(names, cap.node)
    end
    imports = ImportStatement[]
    for (rf, rt, line) in regions
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
        push!(imports, ImportStatement(module_name, imported, line))
    end
    return imports
end

# One splice target an imports query tagged (`@include.path`): the `path` string with quotes
# and all, for the linkage resolver to map to a corpus path, the byte range of the capture,
# which locates the namespace the splice lands in, and the 1-based line of the call that
# spliced it.
struct SpliceTarget
    path::String
    from::Int
    to::Int
    line::Int
end

# The splice targets an imports query tags in one file.
function include_targets(tree::TreeSitter.Tree, query::TreeSitter.Query, source::AbstractString)
    targets = SpliceTarget[]
    for cap in TreeSitter.each_capture(tree, query, source)
        TreeSitter.capture_name(query, cap) == "include.path" || continue
        from, to = TreeSitter.byte_range(cap.node)
        push!(targets, SpliceTarget(String(TreeSitter.slice(source, cap.node)), from, to, line_of(cap.node)))
    end
    return targets
end

# Every linkage target one file declares, each as the string its language's resolver maps to
# corpus paths and the 1-based line the statement sits on: an import statement's module and
# a splice target alike. The file graph records these against the edge each admits, so a
# finding about a dependency can name the statement to drop.
#
# One walk over the captures, not `file_imports` and `include_targets` in turn. The two
# readings want different things from the same query, and a dependency edge needs neither
# the imported name set nor the splice target's byte range, so walking twice would build
# both to discard both. An import statement naming no module declares nothing and is
# dropped, as it is for visibility.
function declared_targets(file::ParsedFile)
    query = imports_query_for(file)
    query === nothing && return Tuple{String, Int}[]
    regions = Tuple{Int, Int, Int}[]
    froms = TreeSitter.Node[]
    targets = Tuple{String, Int}[]
    for cap in TreeSitter.each_capture(file.tree, query, file.source)
        name = TreeSitter.capture_name(query, cap)
        if name == "import"
            push!(regions, (TreeSitter.byte_range(cap.node)..., line_of(cap.node)))
        elseif name == "import.from"
            push!(froms, cap.node)
        elseif name == "include.path"
            push!(targets, (String(TreeSitter.slice(file.source, cap.node)), line_of(cap.node)))
        end
    end
    for (rf, rt, line) in regions
        for node in froms
            nf, nt = TreeSitter.byte_range(node)
            rf <= nf && nt <= rt || continue
            push!(targets, (String(strip(TreeSitter.slice(file.source, node))), line))
            break
        end
    end
    return targets
end

# Every corpus path one file's declared targets name, each paired with the 1-based line of
# the statement naming it. The resolution half of a declared dependency: which language a
# file is written in, what its statements point at, and where its resolver maps them all
# live here, so the file graph is left with the node lookup and nothing else. A file whose
# language has no linkage entry declares nothing this way.
function resolved_targets(file::ParsedFile, corpus::Corpus)
    link = get(LINKAGES, file.language, nothing)
    link === nothing && return Tuple{String, Int}[]
    out = Tuple{String, Int}[]
    for (target, line) in declared_targets(file)
        for path in link.resolve_target(target, file.file, corpus)::Vector{String}
            push!(out, (path, line))
        end
    end
    return out
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
    caps = file.index.scope_captures
    isempty(caps.scopes) && return table
    imports = imports_query_for(file)
    regions = imports === nothing ? ModuleRegion[] : module_regions(file.tree, imports, file.source)
    root = root_scope(caps.scopes)
    namespaces = Set{Tuple{Int, Int}}([(root.from, root.to)])
    for r in regions
        push!(namespaces, (r.from, r.to))
    end
    units = file.index.units
    uranges = Tuple{Int, Int}[unit_span(u) for u in units]
    link = get(LINKAGES, file.language, nothing)
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
        external = link !== nothing && link.external_root(d, file.source)::Bool
        push!(table.defs, CorpusDef(file.file, nodeid(d), name, kind, path, unit, line, def_visibility(file, d), external))
    end
    return table
end

# The splice path of a file the graph never reaches: a file in an include cycle with no
# root above it, which belongs to no namespace the corpus can name.
const NO_NAMESPACE = String[]

# The corpus-wide indexes `visible_defs` shares across files when resolving each file's
# cross-file candidates: the symbol table and corpus path set, the inclusion roots with
# their per-component definition lists and per-file splice paths (splice), and the
# per-file, per-directory definition and export lookups (import, directory, package).
# Grouped so the per-file resolver takes one context, not a long parameter list. Concrete
# fields, so `file_visible` dispatches statically.
struct VisibilityIndex
    table::SymbolTable
    corpus::Corpus
    roots::Dict{String, Int}
    bycomp::Dict{Int, Vector{Int}}
    splices::Dict{String, Vector{String}}
    defs_by_dir::Dict{String, Vector{Int}}
    defs_by_file::Dict{String, Vector{Int}}
    exports_by_file::Dict{String, Set{String}}
end

# The name a definition is visible under from another file that shares its namespace,
# qualified by the module enclosing it directly: the innermost name of its own module
# path, or, at file scope, of the path its file was spliced into. Nothing where neither
# names a module, and for a language that reaches no namespace by qualifying it.
function qualified_name(d::CorpusDef, access::Union{ModuleAccess, Nothing}, splice::Vector{String})
    access === nothing && return nothing
    isempty(d.module_path) || return string(last(d.module_path), access.separator, d.name)
    isempty(splice) && return nothing
    return string(last(splice), access.separator, d.name)
end

# The cross-file names a file sees from a set of candidate definitions: every member's
# name, its own file's excluded. Shared by the splice model, whose members are an
# inclusion component, and the directory model, whose members are a package directory.
# Where the language reaches a namespace by qualifying it, a member also answers to its
# qualified name: that is the only form for a member the language does not export across
# the boundary, and a second form for one spliced into a module, which a caller in
# another namespace writes rather than the bare name.
function member_visible(f::ParsedFile, vi::VisibilityIndex, link::Linkage, members::Vector{Int})
    names = Dict{String, Vector{Int}}()
    access = get(MODULE_ACCESS, f.language, nothing)
    for di in members
        d = vi.table.defs[di]
        d.file == f.file && continue
        link.is_exported(d, Set{String}())::Bool && push!(get!(() -> String[], names, d.name), di)
        key = qualified_name(d, access, get(vi.splices, d.file, NO_NAMESPACE))
        key === nothing && continue
        push!(get!(() -> String[], names, key), di)
    end
    return names
end

# The cross-file names an import file sees: for each import statement, the definitions
# in the resolved module file whose name the import brings in and the module exports.
function import_visible(
        f::ParsedFile, table::SymbolTable, link::Linkage, corpus::Corpus,
        defs_by_file::Dict{String, Vector{Int}}, exports_by_file::Dict{String, Set{String}}
    )
    names = Dict{String, Vector{Int}}()
    for statement in file_imports(f)
        for path in link.resolve_target(statement.module_name, f.file, corpus)::Vector{String}
            exports = get(() -> Set{String}(), exports_by_file, path)
            for di in get(defs_by_file, path, Int[])
                d = table.defs[di]
                d.file == f.file && continue
                link.is_exported(d, exports)::Bool || continue
                (isempty(statement.names) || d.name in statement.names) || continue
                push!(get!(() -> String[], names, d.name), di)
            end
        end
    end
    return names
end

# The same-package type names a file sees: the top-level types its sibling files in the
# same directory declare, the names a package-scoped language (Java) resolves without an
# import. Only a type is exposed, not a method, since a method is reached through a
# receiver, not a bare same-package name; a top-level type name is unique within a package,
# so the match is collision-free. The file's own definitions are excluded.
function package_visible(f::ParsedFile, table::SymbolTable, members::Vector{Int})
    names = Dict{String, Vector{Int}}()
    for di in members
        d = table.defs[di]
        (d.file == f.file || !is_type_kind(d.kind)) && continue
        push!(get!(() -> Int[], names, d.name), di)
    end
    return names
end

# Union two visibility maps, concatenating the candidate lists a name resolves to in
# either, so a file that sees a name through both an import and its package keeps both.
function merge_visible(a::Dict{String, Vector{Int}}, b::Dict{String, Vector{Int}})
    out = Dict{String, Vector{Int}}(name => copy(dis) for (name, dis) in a)
    for (name, dis) in b
        append!(get!(() -> Int[], out, name), dis)
    end
    for dis in values(out)
        unique!(dis)
    end
    return out
end

# The corpus definitions one file can reference across the boundary, indexed by name. The
# linkage model selects the resolver; every input is read-only, so this runs per file in
# parallel from `visible_defs`.
function file_visible(f::ParsedFile, vi::VisibilityIndex)
    link = get(LINKAGES, f.language, nothing)
    link === nothing && return Dict{String, Vector{Int}}()
    link.model === :splice && return member_visible(f, vi, link, get(vi.bycomp, vi.roots[f.file], Int[]))
    link.model === :directory && return member_visible(f, vi, link, get(vi.defs_by_dir, dirname(f.file), Int[]))
    link.model === :package && return merge_visible(
        import_visible(f, vi.table, link, vi.corpus, vi.defs_by_file, vi.exports_by_file),
        package_visible(f, vi.table, get(vi.defs_by_dir, dirname(f.file), Int[])),
    )
    return import_visible(f, vi.table, link, vi.corpus, vi.defs_by_file, vi.exports_by_file)
end
