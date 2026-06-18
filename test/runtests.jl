using Dendro, TreeSitter, Test
using Dendro: analyze, active, Finding, Findings, Location

# A parser and profile for one language, the recurring setup across unit tests.
fixture(lang) = (Dendro.parser_for(lang), Dendro.PROFILES[lang])

# Parse `src` and build its query index, the per-tree node identification every
# metric and flag reads from.
idx(lang, src) =
    Dendro.build_index(parse(Dendro.parser_for(lang), src), Symbol(lang), String(src), Dendro.query_for(lang))

# A ParsedFile for one source, the corpus record clone and naturalness tests need.
function parsedfile(lang, src; file = "f." * string(lang), directives = Dendro.Directive[])
    tree = parse(Dendro.parser_for(lang), src)
    index = Dendro.build_index(tree, Symbol(lang), String(src), Dendro.query_for(lang))
    return Dendro.ParsedFile(Symbol(lang), String(src), file, tree, index, directives)
end

@testset "Dendro" begin
    include("resolve.jl")
    include("parser.jl")
    include("query_index.jl")
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
