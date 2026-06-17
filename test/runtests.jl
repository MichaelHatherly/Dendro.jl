using Dendro, TreeSitter, Test
using Dendro: analyze, active, Finding, Findings, Location

@testset "Dendro" begin
    include("resolve.jl")
    include("parser.jl")
    include("units.jl")
    include("metrics.jl")
    include("flags.jl")
    include("baseline.jl")
    include("report.jl")
    include("suppress.jl")
    include("diff.jl")
    include("corpus.jl")
    include("python.jl")
    include("languages.jl")
    include("dogfood.jl")
end
