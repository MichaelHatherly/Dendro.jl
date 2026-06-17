@testset "parser_for" begin
    # Lazy-loads tree_sitter_julia_jll and returns a working parser.
    p = Dendro.parser_for(:julia)
    @test p isa TreeSitter.Parser
    tree = parse(p, "f(x) = x + 1")
    @test TreeSitter.node_type(TreeSitter.root(tree)) == "source_file"

    # String names normalise to the same parser.
    @test Dendro.parser_for("julia") isa TreeSitter.Parser

    # A missing language reports a helpful error, not a bare lookup failure.
    @test_throws Exception Dendro.parser_for(:nonexistent_language)
end
