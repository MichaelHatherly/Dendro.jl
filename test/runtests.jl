using Dendro, TreeSitter, Test

@testset "Dendro" begin
    include("resolve.jl")
    include("parser.jl")
    include("units.jl")
    include("metrics.jl")
    include("flags.jl")
    include("baseline.jl")
    include("report.jl")
    include("diff.jl")
    include("python.jl")
end
