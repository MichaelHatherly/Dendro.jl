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

@testset "cpp range-based for is a loop" begin
    # tree-sitter-cpp parses `for (auto x : v)` as `for_range_loop`. The query must
    # tag that node so a range-for adds to cyclomatic and nesting like any loop.
    src = "int f(std::vector<int> v){ for(auto a:v){ for(auto b:v){ g(a,b); } } return 0; }"
    i = idx(:cpp, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 3      # base + two range-fors
    @test Dendro.nesting_depth(u.node, i) == 2
end

@testset "rust while-let is a loop" begin
    # `while let` parses as `while_expression`, already tagged, so it counts as one
    # decision point.
    src = "fn f(){ while let Some(x)=it.next() { g(x); } }"
    i = idx(:rust, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 2
end

for case in LANGUAGE_CASES
    @testset "$(case.lang) profile" begin
        i = idx(case.lang, case.src)

        units = Dendro.functions(i)
        @test length(units) == 1
        u = only(units)
        @test Dendro.unit_name(u, i) == "f"
        @test Dendro.cyclomatic(u.node, i) == case.cyclomatic
        @test Dendro.cognitive_complexity(u.node, i) == case.cognitive
        @test Dendro.parameter_count(u.node, i) == case.params
        @test Dendro.nesting_depth(u.node, i) == case.nesting
        @test Dendro.function_length(u) == case.length
        @test Dendro.boolean_complexity(u.node, i) == case.boolean
        @test Dendro.return_count(u.node, i) == case.returns
        @test length(Dendro.empty_catches(i)) == case.catches
        @test length(Dendro.stub_markers(i)) == case.stubs
    end
end
