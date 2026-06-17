@testset "function units (julia)" begin
    p, prof = fixture(:julia)
    src = "function f(x)\n    x + 1\nend\nfunction g()\n    0\nend\n"
    tree = parse(p, src)
    units = Dendro.functions(tree, prof)
    @test length(units) == 2
    @test TreeSitter.node_type(units[1].node) == "function_definition"
    @test units[1].firstline == 1
    @test units[1].lastline == 3
    @test units[2].firstline == 4
end
