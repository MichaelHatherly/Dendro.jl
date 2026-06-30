# Shared setup for the test items. Evaluated once; items reach its contents
# qualified, e.g. `Fixtures.idx(:julia, src)`.
@testmodule Fixtures begin
    import Dendro
    import TreeSitter

    # A parser and profile for one language, the recurring setup across unit tests.
    fixture(lang) = (Dendro.parser_for(lang), Dendro.PROFILES[lang])

    # Parse `src` and build its query index, the per-tree node identification every
    # metric and flag reads from. The scopes query is threaded through so the index
    # carries bindings for languages that ship one.
    idx(lang, src) =
        Dendro.build_index(
        TreeSitter.parse(Dendro.parser_for(lang), src), Symbol(lang), String(src),
        Dendro.query_for(lang), Dendro.scopes_query_for(Symbol(lang))
    )

    # A ParsedFile for one source, the corpus record clone and naturalness tests need.
    function parsedfile(lang, src; file = "f." * string(lang), directives = Dendro.Directive[])
        tree = TreeSitter.parse(Dendro.parser_for(lang), src)
        index = Dendro.build_index(
            tree, Symbol(lang), String(src), Dendro.query_for(lang),
            Dendro.scopes_query_for(Symbol(lang))
        )
        return Dendro.ParsedFile(Symbol(lang), String(src), file, tree, index, directives)
    end

    # The bindings resolved for `src`, the type-stable entry the binding test asserts
    # inference on. Narrows the scopes query past its `nothing` case before the call.
    function resolve(lang, src)
        tree = TreeSitter.parse(Dendro.parser_for(lang), src)
        query = Dendro.scopes_query_for(Symbol(lang))
        query === nothing && error("no scopes query for $lang")
        return Dendro.resolve_bindings!(Dict{Dendro.NodeId, Dendro.NodeId}(), tree, query, String(src))
    end

    # Each resolved binding as `(ref_text, ref_line) => (def_text, def_line)`, the
    # readable form the binding tests assert on.
    function binding_pairs(index)
        info = Dict{Dendro.NodeId, Tuple{String, Int}}()
        for n in index.name.nodes
            info[Dendro.nodeid(n)] = (String(strip(TreeSitter.slice(index.source, n))), Int(TreeSitter.start_point(n).row) + 1)
        end
        pairs = Pair{Tuple{String, Int}, Tuple{String, Int}}[]
        for (r, d) in index.bindings
            push!(pairs, info[r] => info[d])
        end
        return pairs
    end

    # Findings of one relational metric, the filters the clone and corpus items share.
    duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :duplicate, findings))
    near_duplicates(findings) = Dendro.Findings(filter(f -> f.metric == :near_duplicate, findings))

    # The (file, unit) sites the dead-code pass flags over a corpus, the readable form the
    # unreferenced items assert on.
    unref_sites(files) =
        Set((loc.file, loc.unit) for f in Dendro.cluster_unreferenced(files, Dendro.corpus_symbols(files)) for loc in f.locations)

    # A Julia function whose body is `n` chained assignments. Two such with different
    # names are renamed clones; with different `n` they are near-misses. Each statement
    # adds 7 named nodes, so `n` controls the size band.
    chain(name, n) = string(
        "function $name($(name)0)\n",
        join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
        "    return $name$n\nend\n"
    )

    pychain(name, n) = string(
        "def $name($(name)0):\n",
        join("    $name$i = $name$(i - 1) + $i\n" for i in 1:n),
        "    return $name$n\n"
    )

    # --- Ratchet fixtures -----------------------------------------------------
    # The gate ratchet (`errors(; since)`) is exercised against throwaway git repos.
    # `gitrepo()` returns `(root, src)`: an initialised repo with an empty `src/` folder
    # and a local identity so commits work in CI. `commit!` stages and commits quietly,
    # so test output stays pristine.
    function gitrepo()
        root = mktempdir()
        run(pipeline(`git -C $root init -q`; stdout = devnull, stderr = devnull))
        run(pipeline(`git -C $root config user.email dendro@test`; stdout = devnull, stderr = devnull))
        run(pipeline(`git -C $root config user.name Dendro`; stdout = devnull, stderr = devnull))
        src = joinpath(root, "src")
        mkpath(src)
        return root, src
    end

    function commit!(root, msg)
        run(pipeline(`git -C $root add .`; stdout = devnull, stderr = devnull))
        run(pipeline(`git -C $root commit -q -m $msg`; stdout = devnull, stderr = devnull))
        return nothing
    end

    # A single-file Julia module whose exported `run` calls each of `calls`, so every
    # helper is reachable and the unreferenced pass stays quiet. `defs` is the helper
    # source spliced after `run`.
    modsrc(calls, defs) = string("module M\nexport run\nrun() = (", join(calls, "; "), ")\n", defs, "\nend\n")

    # A function nesting six `if` blocks, so its `nesting_depth` of 6 trips the `:high`
    # band. The argument seeds every guard, keeping the body self-contained.
    function deepfn(name)
        body = "return $(name)0"
        for i in 6:-1:1
            body = "if $(name)0 > $i\n$body\nend"
        end
        return "function $name($(name)0)\n$body\nend\n"
    end

    # A function with `n` empty `catch` blocks, so it carries `n` `:empty_catch` flags.
    catchfn(name, n) = string(
        "function $name($(name)0)\n",
        join("    try\n        g($(name)0)\n    catch\n    end\n" for _ in 1:n),
        "    return $(name)0\nend\n"
    )

    # A custom flag rule a caller might supply: comments carrying a BUG marker. Mirrors
    # the built-in stub_marker rule, but names a metric Dendro does not ship.
    bug_markers(index) =
        [n for n in index.comment.nodes if occursin("BUG", TreeSitter.slice(index.source, n))]

    const BUG_RULE = Dendro.Rule(:bug_marker, :flag, nothing, bug_markers)

    # One fixture per language, exercising the verified core: a function with two
    # parameters, an `if` guarded by a short-circuit operator, plus a loop or an
    # empty catch. Expected metric values are hand-derived from that structure.
    const LANGUAGE_CASES = [
        (
            lang = :bash, src = "f() {\n  # TODO\n  if [ \"\$1\" -gt 0 ] && [ \"\$2\" -gt 0 ]; then\n    for i in 1 2; do echo \$i; done\n  fi\n}\n",
            cyclomatic = 4, cognitive = 4, params = 0, catches = 0, stubs = 1, nesting = 2, length = 6, boolean = 1, returns = 0,
        ),
        (
            lang = :c, src = "int f(int x, int y) {\n  // TODO\n  if (x > 0 && y > 0) {\n    for (int i = 0; i < x; i++) { }\n  }\n  return 0;\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 0, stubs = 1, nesting = 2, length = 7, boolean = 1, returns = 1,
        ),
        (
            lang = :cpp, src = "int f(int x, int y) {\n  if (x > 0 && y > 0) { }\n  try { g(); } catch (...) { }\n  return 0;\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 1, stubs = 0, nesting = 1, length = 5, boolean = 1, returns = 1,
        ),
        (
            lang = :go, src = "func f(x int, y int) int {\n  if x > 0 && y > 0 {\n    for i := 0; i < x; i++ { }\n  }\n  return 0\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 0, stubs = 0, nesting = 2, length = 6, boolean = 1, returns = 1,
        ),
        (
            lang = :java, src = "class C {\n  int f(int x, int y) {\n    if (x > 0 && y > 0) { }\n    try { g(); } catch (Exception e) { }\n    return 0;\n  }\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 1, stubs = 0, nesting = 1, length = 5, boolean = 1, returns = 1,
        ),
        (
            lang = :javascript, src = "function f(x, y) {\n  if (x > 0 && y > 0) { }\n  try { g(); } catch (e) { }\n  return 0;\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 1, stubs = 0, nesting = 1, length = 5, boolean = 1, returns = 1,
        ),
        (
            lang = :php, src = "<?php\nfunction f(\$x, \$y) {\n  if (\$x > 0 && \$y > 0) { }\n  try { g(); } catch (Exception \$e) { }\n  return 0;\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 1, stubs = 0, nesting = 1, length = 5, boolean = 1, returns = 1,
        ),
        (
            lang = :ruby, src = "def f(x, y)\n  # TODO\n  if x > 0 && y > 0\n    z = 1\n  end\nend\n",
            cyclomatic = 3, cognitive = 2, params = 2, catches = 0, stubs = 1, nesting = 1, length = 6, boolean = 1, returns = 0,
        ),
        (
            lang = :rust, src = "fn f(x: i32, y: i32) -> i32 {\n  if x > 0 && y > 0 {\n    while x > 0 { }\n  }\n  0\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 0, stubs = 0, nesting = 2, length = 6, boolean = 1, returns = 0,
        ),
        (
            lang = :typescript, src = "function f(x: number, y: number): number {\n  if (x > 0 && y > 0) { }\n  try { g(); } catch (e) { }\n  return 0;\n}\n",
            cyclomatic = 4, cognitive = 4, params = 2, catches = 1, stubs = 0, nesting = 1, length = 5, boolean = 1, returns = 1,
        ),
    ]

    # One binding fixture per language: a two-function source where `f` calls
    # `helper`. The cohesion edge is the call reference binding to the sibling
    # definition. `ref`/`def` are the 1-based lines of the call and the definition,
    # hand-read from each source. Proves the scopes query compiles and the core edge
    # forms in every language Dendro parses.
    const LANGUAGE_BINDING_CASES = [
        (lang = :bash, src = "helper() {\n  echo \$1\n}\nf() {\n  helper \$1\n}\n", ref = 5, def = 1),
        (lang = :c, src = "int helper(int x) { return x + 1; }\nint f(int a) { return helper(a); }\n", ref = 2, def = 1),
        (lang = :cpp, src = "int helper(int x) { return x + 1; }\nint f(int a) { return helper(a); }\n", ref = 2, def = 1),
        (lang = :go, src = "package m\nfunc helper(x int) int { return x + 1 }\nfunc f(a int) int { return helper(a) }\n", ref = 3, def = 2),
        (lang = :java, src = "class C {\n  int helper(int x) { return x + 1; }\n  int f(int a) { return helper(a); }\n}\n", ref = 3, def = 2),
        (lang = :javascript, src = "function helper(x) { return x + 1; }\nfunction f(a) { return helper(a); }\n", ref = 2, def = 1),
        (lang = :php, src = "<?php\nfunction helper(\$x) { return \$x + 1; }\nfunction f(\$a) { return helper(\$a); }\n", ref = 3, def = 2),
        (lang = :python, src = "def helper(x):\n    return x + 1\ndef f(a):\n    return helper(a)\n", ref = 4, def = 1),
        (lang = :ruby, src = "def helper(x)\n  x + 1\nend\ndef f(a)\n  helper(a)\nend\n", ref = 5, def = 1),
        (lang = :rust, src = "fn helper(x: i32) -> i32 { x + 1 }\nfn f(a: i32) -> i32 { helper(a) }\n", ref = 2, def = 1),
        (lang = :typescript, src = "function helper(x: number): number { return x + 1; }\nfunction f(a: number): number { return helper(a); }\n", ref = 2, def = 1),
    ]

    # NPath per grammar: one construct per case, the value hand-derived from PMD's rules
    # (sequences multiply, branches add, each `&&`/`||` in a condition adds one, a switch
    # sums its case bodies). Ruby and Bash are absent: their branch bodies are not block
    # nodes, so the construct families are not wired.
    # --- Real-file corpus -----------------------------------------------------
    # A hand-written per-language corpus under `test/corpus/<lang>/`, run end to end
    # through `analyze`. Each planted finding is tagged inline with a `dendro-expect`
    # marker (mirroring `dendro-ignore`); the corpus test asserts the findings match
    # the markers exactly. Scoring is absolute-band only (cut > 1), as the dogfood
    # gate is, so the result does not depend on the corpus distribution.

    corpus_root() = joinpath(pkgdir(Dendro), "test", "corpus")
    corpus_langs() = sort([d for d in readdir(corpus_root()) if isdir(joinpath(corpus_root(), d))])

    # Metrics the corpus assertion tracks. `:unnatural` is excluded: it is a corpus
    # statistic, not a structural smell with a fixed site to mark.
    const TRACKED_METRICS = Set{Symbol}(
        [
            :cyclomatic, :cognitive_complexity, :function_length, :nesting_depth,
            :parameter_count, :boolean_complexity,
            :identical_operands, :duplicate_branches, :empty_body, :empty_catch,
            :stub_marker, :return_in_finally,
            :duplicate, :near_duplicate, :low_cohesion, :misplaced, :scattered,
        ]
    )

    # Metrics reported per file, not at a code line. Their marker is file-scoped
    # (`dendro-expect-file:`), matched when the file carries the metric at all.
    const FILE_METRICS = Set{Symbol}([:low_cohesion, :scattered])

    # Metrics whose finding carries a suggested target as a second location. Only the
    # first location, the flagged unit, is the marked site; the target is a hint.
    const FIRST_LOCATION_METRICS = Set{Symbol}([:misplaced])

    const EXPECT_RE = r"\bdendro-expect(-file)?\s*:\s*([\w,\s]+)"i

    # Parse `dendro-expect` markers from one source's comments, reusing the comment
    # walk and metric-list split `suppressions` uses. Returns line-scoped markers as
    # `(line, metric)` and file-scoped markers as `metric`, validated against
    # `TRACKED_METRICS`.
    function expect_markers(lang, source)
        i = idx(lang, source)
        line = Set{Tuple{Int, Symbol}}()
        file = Set{Symbol}()
        for n in i.comment.nodes
            for m in eachmatch(EXPECT_RE, String(TreeSitter.slice(i.source, n)))
                for tok in split(m.captures[2], r"[,\s]+"; keepempty = false)
                    sym = Symbol(strip(tok))
                    sym in TRACKED_METRICS || error("corpus marker names unknown metric: $sym")
                    m.captures[1] === nothing ? push!(line, (Dendro.line_of(n), sym)) : push!(file, sym)
                end
            end
        end
        return (; line, file)
    end

    # Compare a language corpus's findings against its inline markers. Returns
    # `(unexpected, missing)` as sorted strings; both empty means the corpus matched.
    # A line marker matches a finding on its own line or the line below (the
    # `is_suppressed` tolerance); duplicate and near-duplicate findings are matched
    # per member location, low cohesion per file.
    function corpus_mismatch(lang)
        dir = joinpath(corpus_root(), string(lang))
        findings = Dendro.active(Dendro.analyze(dir; cut = 2.0))

        line_exp = Set{Tuple{String, Int, Symbol}}()
        file_exp = Set{Tuple{String, Symbol}}()
        for path in Dendro.source_files(dir)
            mk = expect_markers(Dendro.language_for_path(path), read(path, String))
            for (ln, mt) in mk.line
                push!(line_exp, (path, ln, mt))
            end
            for mt in mk.file
                push!(file_exp, (path, mt))
            end
        end

        line_site = Set{Tuple{String, Int, Symbol}}()
        file_site = Set{Tuple{String, Symbol}}()
        for f in findings
            f.metric in TRACKED_METRICS || continue
            locs = f.metric in FIRST_LOCATION_METRICS ? f.locations[1:1] : f.locations
            for loc in locs
                f.metric in FILE_METRICS ? push!(file_site, (loc.file, f.metric)) :
                    push!(line_site, (loc.file, loc.line, f.metric))
            end
        end

        # A site at line F is expected by a marker at F (trailing) or F - 1 (above).
        site_ok(p, l, mt) = (p, l, mt) in line_exp || (p, l - 1, mt) in line_exp
        mark_ok(p, c, mt) = (p, c, mt) in line_site || (p, c + 1, mt) in line_site

        unexpected = sort([string(p, ":", l, " ", mt) for (p, l, mt) in line_site if !site_ok(p, l, mt)])
        append!(unexpected, sort([string(p, " ", mt, " (file)") for (p, mt) in file_site if !((p, mt) in file_exp)]))
        missing = sort([string(p, ":", c, " ", mt) for (p, c, mt) in line_exp if !mark_ok(p, c, mt)])
        append!(missing, sort([string(p, " ", mt, " (file)") for (p, mt) in file_exp if !((p, mt) in file_site)]))
        return (; unexpected, missing)
    end

    const NPATH_CASES = [
        (lang = :c, name = "if", src = "int f(int x){ if(x>0){a();} }", npath = 2),
        (lang = :c, name = "ifelse", src = "int f(int x){ if(x>0){a();}else{b();} }", npath = 2),
        (lang = :c, name = "while", src = "int f(int x){ while(x>0){a();} }", npath = 2),
        (lang = :c, name = "switch", src = "int f(int x){ switch(x){case 1:a();break;case 2:b();break;default:c();} }", npath = 3),
        (lang = :c, name = "ternary", src = "int f(int x){ return x>0?a():b(); }", npath = 2),
        (lang = :c, name = "bools", src = "int f(int x){ if(x>0&&x<9){a();} }", npath = 3),
        (lang = :cpp, name = "try", src = "int f(){ try{a();}catch(...){b();} return 0; }", npath = 2),
        (lang = :go, name = "switch", src = "func f(x int){ switch x { case 1: a(); default: b() } }", npath = 2),
        (lang = :go, name = "ifelseif", src = "func f(x int){ if x>0 {a()} else if x<0 {b()} else {c()} }", npath = 3),
        (lang = :java, name = "switch", src = "class C{ void f(int x){ switch(x){ case 1: a(); break; default: b(); } } }", npath = 2),
        (lang = :java, name = "tryfinally", src = "class C{ void f(){ try{a();}catch(Exception e){b();}finally{c();} } }", npath = 3),
        (lang = :javascript, name = "switch", src = "function f(x){ switch(x){ case 1: a(); break; default: b(); } }", npath = 2),
        (lang = :typescript, name = "try", src = "function f(){ try{a();}catch(e){b();} }", npath = 2),
        (lang = :php, name = "ternary", src = "<?php function f(\$x){ return \$x>0?a():b(); }", npath = 2),
        (lang = :php, name = "foreach", src = "<?php function f(\$xs){ foreach(\$xs as \$x){ g(\$x); } }", npath = 2),
        (lang = :rust, name = "match", src = "fn f(x: i32){ match x { 1 => a(), _ => b() } }", npath = 2),
        (lang = :rust, name = "ifelseif", src = "fn f(x: i32){ if x>0 { a(); } else if x<0 { b(); } else { c(); } }", npath = 3),
        (lang = :python, name = "match", src = "def f(x):\n    match x:\n        case 1:\n            a()\n        case _:\n            b()\n", npath = 2),
        (lang = :python, name = "tryfinally", src = "def f(x):\n    try:\n        a()\n    except E:\n        b()\n    finally:\n        c()\n", npath = 3),
        # Python places the ternary condition in the middle (`a if c else b`); its `&&`
        # must still count, which the order-agnostic rule handles.
        (lang = :python, name = "ternary_bool", src = "def f(x):\n    return a() if x>0 and x<9 else b()\n", npath = 3),
    ]
end
