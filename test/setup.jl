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

    # NPath per grammar: one construct per case, the value hand-derived from PMD's rules
    # (sequences multiply, branches add, each `&&`/`||` in a condition adds one, a switch
    # sums its case bodies). Ruby and Bash are absent: their branch bodies are not block
    # nodes, so the construct families are not wired.
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
