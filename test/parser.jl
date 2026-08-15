@testitem "parser_for" tags = [:parser] begin
    using TreeSitter

    # Lazy-loads tree_sitter_julia_jll and returns a working parser.
    p = Dendro.parser_for(:julia)
    @test p isa TreeSitter.Parser
    tree = parse(p, "f(x) = x + 1")
    @test TreeSitter.node_type(TreeSitter.root(tree)) == "source_file"

    # String names normalise to the same parser.
    @test Dendro.parser_for("julia") isa TreeSitter.Parser

    # A missing language reports a helpful error, not a bare lookup failure.
    @test_throws "no parser for language" Dendro.parser_for(:nonexistent_language)
end

@testitem "parse_source" tags = [:parser] begin
    using TreeSitter

    # The Julia grammar injects markdown into a docstring and a comment language into
    # every comment, so this source gives the injections query sites to find.
    src = """
    "A docstring."
    f(x) = x + 1  # a comment
    """
    parser = Dendro.parser_for(:julia)

    # What the default parse does with those sites, which is what makes the assertion
    # below say something.
    injected = parse(parser, src)
    @test !isempty(injected.children) || !isempty(injected.unresolved)

    # Dendro reads the root layer alone, so its parse builds no layer at all.
    tree = Dendro.parse_source(parser, src)
    @test isempty(tree.children)
    @test isempty(tree.unresolved)

    # The root layer is unchanged, so every query Dendro runs reads the same tree.
    root = TreeSitter.root(tree)
    @test TreeSitter.node_type(root) == "source_file"
    @test TreeSitter.byte_range(root) == TreeSitter.byte_range(TreeSitter.root(injected))
end
