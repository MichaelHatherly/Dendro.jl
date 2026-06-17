using Dendro, TreeSitter, Test

@testset "Dendro" begin
    include("resolve.jl")
    include("parser.jl")
    include("units.jl")
    include("metrics.jl")
end
