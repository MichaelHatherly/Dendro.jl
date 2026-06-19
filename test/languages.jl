@testitem "cpp range-based for is a loop" setup = [Fixtures] tags = [:languages] begin
    # tree-sitter-cpp parses `for (auto x : v)` as `for_range_loop`. The query must
    # tag that node so a range-for adds to cyclomatic and nesting like any loop.
    src = "int f(std::vector<int> v){ for(auto a:v){ for(auto b:v){ g(a,b); } } return 0; }"
    i = Fixtures.idx(:cpp, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 3      # base + two range-fors
    @test Dendro.nesting_depth(u.node, i) == 2
end

@testitem "rust while-let is a loop" setup = [Fixtures] tags = [:languages] begin
    # `while let` parses as `while_expression`, already tagged, so it counts as one
    # decision point.
    src = "fn f(){ while let Some(x)=it.next() { g(x); } }"
    i = Fixtures.idx(:rust, src)
    u = only(Dendro.functions(i))
    @test Dendro.cyclomatic(u.node, i) == 2
end

@testitem "npath per grammar" setup = [Fixtures] tags = [:languages] begin
    @testset "npath $(case.lang)/$(case.name)" for case in Fixtures.NPATH_CASES
        i = Fixtures.idx(case.lang, case.src)
        u = only(Dendro.functions(i))
        @test Dendro.npath(u.node, i) == case.npath
    end
end

@testitem "language profiles" setup = [Fixtures] tags = [:languages] begin
    for case in Fixtures.LANGUAGE_CASES
        @testset "$(case.lang) profile" begin
            i = Fixtures.idx(case.lang, case.src)

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
end
