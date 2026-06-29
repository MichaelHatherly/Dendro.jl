@testitem "corpus graph resolves a cross-file call through an include splice" setup = [Fixtures] tags = [:corpus_graph] begin
    main = Fixtures.parsedfile(:julia, "include(\"util.jl\")\nf(x) = helper(x) + 1\n"; file = "main.jl")
    util = Fixtures.parsedfile(:julia, "helper(y) = y * 2\n"; file = "util.jl")
    files = [main, util]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `f` in main.jl calls `helper`, defined in util.jl, which main.jl splices in via
    # `include`. The reference resolves across the file boundary to helper's unit, the
    # whole point of the corpus graph.
    fidx = graph.unit_index[("main.jl", 1)]
    hidx = graph.unit_index[("util.jl", 1)]
    @test haskey(graph.edges, (fidx, hidx))
    @test graph.edges[(fidx, hidx)] ≈ 1.0
    # The placement signal: all of f's cross-file reference mass lands in util.jl.
    @test graph.file_mass[fidx]["util.jl"] ≈ 1.0
    # f and helper couple, so community detection puts them together.
    comm = Dendro.communities(graph)
    @test comm[fidx] == comm[hidx]
end

@testitem "corpus graph leaves files with no include link unconnected" setup = [Fixtures] tags = [:corpus_graph] begin
    a = Fixtures.parsedfile(:julia, "f(x) = helper(x)\n"; file = "a.jl")
    b = Fixtures.parsedfile(:julia, "helper(y) = y\n"; file = "b.jl")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # No `include` connects a.jl and b.jl, so `helper` is not visible across the
    # boundary. The reference stays unresolved: no cross-file edge, no invented link.
    @test isempty(graph.edges)
end

@testitem "corpus graph resolves a Python from-import across files" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:python, "def helper(x):\n    return x\n"; file = "pkg/util.py")
    main = Fixtures.parsedfile(:python, "from .util import helper\ndef use(a):\n    return helper(a)\n"; file = "pkg/main.py")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use` in main.py calls `helper`, brought into scope by `from .util import helper`.
    # The relative import resolves to pkg/util.py, so the reference crosses the file
    # boundary to helper's unit.
    uidx = graph.unit_index[("pkg/main.py", 1)]
    hidx = graph.unit_index[("pkg/util.py", 1)]
    @test haskey(graph.edges, (uidx, hidx))
    @test graph.file_mass[uidx]["pkg/util.py"] ≈ 1.0
end

@testitem "corpus graph honours a Python import's name list" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:python, "def helper(x):\n    return x\ndef other(y):\n    return y\n"; file = "u.py")
    # `main` imports only `helper`; its call to `other` is not in scope, so it stays
    # unresolved. The import list gates visibility, name by name.
    main = Fixtures.parsedfile(:python, "from .u import helper\ndef use(a):\n    return helper(a) + other(a)\n"; file = "m.py")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    uidx = graph.unit_index[("m.py", 1)]
    helper_idx = graph.unit_index[("u.py", 1)]
    other_idx = graph.unit_index[("u.py", 2)]
    @test haskey(graph.edges, (uidx, helper_idx))
    @test !haskey(graph.edges, (uidx, other_idx))
end

@testitem "corpus graph resolves a JavaScript named import" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:javascript, "export function helper(x) { return x; }\n"; file = "util.js")
    main = Fixtures.parsedfile(:javascript, "import { helper } from './util';\nfunction use(a) { return helper(a); }\n"; file = "main.js")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use` calls `helper`, brought in by the named import from './util'. The relative
    # specifier resolves to util.js, so the reference crosses the file boundary.
    uidx = graph.unit_index[("main.js", 1)]
    hidx = graph.unit_index[("util.js", 1)]
    @test haskey(graph.edges, (uidx, hidx))
end

@testitem "corpus graph hides a JavaScript name that is not exported" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:javascript, "export function helper(x) { return x; }\nfunction secret(y) { return y; }\n"; file = "u.js")
    main = Fixtures.parsedfile(:javascript, "import { helper, secret } from './u';\nfunction use(a) { return helper(a) + secret(a); }\n"; file = "m.js")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    uidx = graph.unit_index[("m.js", 1)]
    helper_idx = graph.unit_index[("u.js", 1)]
    secret_idx = graph.unit_index[("u.js", 2)]
    # `secret` is imported by name but never exported, so it is not visible: no edge.
    @test haskey(graph.edges, (uidx, helper_idx))
    @test !haskey(graph.edges, (uidx, secret_idx))
end

@testitem "corpus graph keeps a JavaScript default import from importing names" setup = [Fixtures] tags = [:corpus_graph] begin
    util = Fixtures.parsedfile(:javascript, "export function helper(x) { return x; }\nexport default function () {}\n"; file = "u.js")
    main = Fixtures.parsedfile(:javascript, "import thing from './u';\nfunction use(a) { return helper(a); }\n"; file = "m.js")
    files = [util, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # A default import binds the module's default export, not its named exports. `helper`
    # is never brought into bare scope, so `use`'s reference does not resolve: no edge.
    # The empty name set of a default import must not be read as a wildcard.
    @test !haskey(graph.edges, (graph.unit_index[("m.js", 1)], graph.unit_index[("u.js", 1)]))
end

@testitem "corpus graph resolves a C include splice" setup = [Fixtures] tags = [:corpus_graph] begin
    header = Fixtures.parsedfile(:c, "int helper(int x) { return x; }\n"; file = "a.h")
    main = Fixtures.parsedfile(:c, "#include \"a.h\"\nint use(int a) { return helper(a); }\n"; file = "b.c")
    files = [header, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # b.c includes a.h, splicing `helper` into scope; the call resolves across files.
    @test haskey(graph.edges, (graph.unit_index[("b.c", 1)], graph.unit_index[("a.h", 1)]))
end

@testitem "corpus graph resolves a Ruby require_relative splice" setup = [Fixtures] tags = [:corpus_graph] begin
    helper = Fixtures.parsedfile(:ruby, "def helper(x)\n  x\nend\n"; file = "helper.rb")
    main = Fixtures.parsedfile(:ruby, "require_relative 'helper'\ndef use(a)\n  helper(a)\nend\n"; file = "main.rb")
    files = [helper, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # require_relative 'helper' loads helper.rb's top-level methods; the call resolves.
    @test haskey(graph.edges, (graph.unit_index[("main.rb", 1)], graph.unit_index[("helper.rb", 1)]))
end

@testitem "corpus graph shares names within a Go package directory" setup = [Fixtures] tags = [:corpus_graph] begin
    a = Fixtures.parsedfile(:go, "package m\nfunc Helper(x int) int { return x }\n"; file = "m/a.go")
    b = Fixtures.parsedfile(:go, "package m\nfunc Use(a int) int { return Helper(a) }\n"; file = "m/b.go")
    files = [a, b]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # Files in one package directory share a namespace, so b.go's call to `Helper`
    # resolves to a.go with no import.
    @test haskey(graph.edges, (graph.unit_index[("m/b.go", 1)], graph.unit_index[("m/a.go", 1)]))
end

@testitem "corpus graph resolves a Rust use import" setup = [Fixtures] tags = [:corpus_graph] begin
    foo = Fixtures.parsedfile(:rust, "pub fn helper() -> i32 { 1 }\n"; file = "foo.rs")
    main = Fixtures.parsedfile(:rust, "use crate::foo::helper;\nfn run() -> i32 { helper() }\n"; file = "main.rs")
    files = [foo, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use crate::foo::helper` resolves module `foo` to foo.rs and brings `helper` in.
    @test haskey(graph.edges, (graph.unit_index[("main.rs", 1)], graph.unit_index[("foo.rs", 1)]))
end

@testitem "corpus graph resolves a Rust grouped use import" setup = [Fixtures] tags = [:corpus_graph] begin
    foo = Fixtures.parsedfile(:rust, "pub fn helper() -> i32 { 1 }\npub fn other() -> i32 { 2 }\n"; file = "foo.rs")
    main = Fixtures.parsedfile(:rust, "use crate::foo::{helper, other};\nfn run() -> i32 { helper() + other() }\n"; file = "main.rs")
    files = [foo, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use crate::foo::{helper, other}` resolves module `foo` and brings both items in,
    # so `run` couples to foo.rs through each call.
    @test haskey(graph.edges, (graph.unit_index[("main.rs", 1)], graph.unit_index[("foo.rs", 1)]))
end

@testitem "corpus graph resolves a Rust wildcard use import" setup = [Fixtures] tags = [:corpus_graph] begin
    foo = Fixtures.parsedfile(:rust, "pub fn helper() -> i32 { 1 }\n"; file = "foo.rs")
    main = Fixtures.parsedfile(:rust, "use crate::foo::*;\nfn run() -> i32 { helper() }\n"; file = "main.rs")
    files = [foo, main]
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # `use crate::foo::*` brings every name from foo.rs into scope, so `helper` resolves.
    @test haskey(graph.edges, (graph.unit_index[("main.rs", 1)], graph.unit_index[("foo.rs", 1)]))
end

@testitem "corpus graph resolves a real cross-file edge in Dendro's own source" tags = [:corpus_graph] begin
    src = joinpath(pkgdir(Dendro), "src")
    files = Dendro.parse_corpus(Dendro.source_files(src))
    table = Dendro.corpus_symbols(files)
    graph = Dendro.build_corpus_graph(files, table)

    # corpus.jl calls `cluster_low_cohesion`, defined in cohesion.jl. The include splice
    # in Dendro.jl puts both files in one module, so the call resolves across files. The
    # realistic integration test for Julia splice resolution.
    found = any(graph.edges) do ((s, d), _)
        endswith(graph.units[s].file, "corpus.jl") && endswith(graph.units[d].file, "cohesion.jl")
    end
    @test found
end
