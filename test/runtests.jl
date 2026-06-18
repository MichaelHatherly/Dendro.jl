using Dendro, TreeSitter, Test
using Dendro: analyze, active, Finding, Findings, Location

# A parser and profile for one language, the recurring setup across unit tests.
fixture(lang) = (Dendro.parser_for(lang), Dendro.PROFILES[lang])

@testset "Dendro" begin
    include("resolve.jl")
    include("parser.jl")
    include("units.jl")
    include("metrics.jl")
    include("flags.jl")
    include("rules.jl")
    include("baseline.jl")
    include("report.jl")
    include("suppress.jl")
    include("diff.jl")
    include("corpus.jl")
    include("ignore.jl")
    include("clones.jl")
    include("naturalness.jl")
    include("python.jl")
    include("languages.jl")
    include("dogfood.jl")
    include("jet.jl")
end
