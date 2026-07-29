@testitem "a fragment expands into a pattern" setup = [Fixtures] tags = [:patterns] begin
    src = """
    ; fragment: loops = [(while_statement) (for_statement)]
    (loops) @any_loop
    """
    # Referencing the fragment by name splices its text, so one rule covers both shapes
    # without repeating them.
    query = replace(src, "(loops) @any_loop" => "@loops @any_loop")
    body = "function f(x)\n    while x\n    end\n    for i in x\n    end\nend\n"
    @test Fixtures.pattern_lines(:julia, body, :any_loop, query) == [2, 4]
end

@testitem "an error inside a fragment names the fragment" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError, compile_pattern_query, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    src = """
    ; fragment: broken = (no_such_node_type)

    (identifier) @ok
    @broken @bad
    """
    err = try
        compile_pattern_query(g, src, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    # The offset lands inside spliced text the author never wrote, so reporting it as a
    # line number would point at nothing. This is the property the feature rests on.
    @test occursin("fragment `broken`", err.msg)
    @test occursin("defined at line 1", err.msg)
    @test occursin("used at line 4", err.msg)
end

@testitem "an error outside a fragment still names its real line" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError, compile_pattern_query, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    src = """
    ; fragment: loops = [(while_statement) (for_statement)]
    @loops @any_loop
    (no_such_node_type) @bad
    """
    err = try
        compile_pattern_query(g, src, "julia.patterns.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    # Line-preserving expansion: the definition line blanks out and the reference expands
    # within its own line, so line 3 is still line 3.
    @test occursin("line 3", err.msg)
    @test !occursin("fragment", err.msg)
end

@testitem "a file with no fragments is unchanged" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: expand_fragments

    src = "(identifier) @a\n((call_expression) @b (#eq? @b \"x\"))\n"
    expanded = expand_fragments(src, "p.scm")
    @test expanded.text == src
    @test isempty(expanded.spans)
end

@testitem "a fragment cannot share a rule's name" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError, PatternSpec, compile_pattern_query, language_grammar, profile_for

    g = language_grammar(profile_for(:julia))
    specs = [PatternSpec(:loops, "m", :warn, :flag, nothing)]
    src = "; fragment: loops = (while_statement)\n@loops @other\n"
    err = try
        compile_pattern_query(g, src, "julia.patterns.scm"; specs)
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("same name as a declared rule", err.msg)
end

@testitem "a fragment defined twice is rejected" setup = [Fixtures] tags = [:patterns] begin
    using Dendro: ConfigError, collect_fragments

    src = "; fragment: a = (identifier)\n; fragment: a = (while_statement)\n"
    err = try
        collect_fragments(src, "p.scm")
        nothing
    catch e
        e
    end
    @test err isa ConfigError
    @test occursin("already defined at line 1", err.msg)
end
