@testitem "language_for_path" tags = [:resolve] begin
    @test Dendro.language_for_path("foo.jl") == :julia
    @test Dendro.language_for_path("a/b/foo.py") == :python
    @test Dendro.language_for_path("script.sh") == :bash
    @test Dendro.language_for_path("main.cpp") == :cpp
    @test Dendro.language_for_path("README.md") === nothing
end
