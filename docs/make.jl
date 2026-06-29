using Documenter
using Dendro

makedocs(;
    modules = [Dendro],
    sitename = "Dendro.jl",
    authors = "Michael Hatherly",
    pages = [
        "Home" => "index.md",
        "Scoring and metrics" => "metrics.md",
        "Duplicate detection" => "duplicates.md",
        "Cohesion and placement" => "cohesion.md",
        "Suppressing findings" => "suppression.md",
        "Custom rules" => "rules.md",
        "Languages and limitations" => "languages.md",
        "API reference" => "api.md",
    ],
    checkdocs = :public,
    warnonly = false,
)

deploydocs(;
    repo = "github.com/MichaelHatherly/Dendro.jl",
    push_preview = true,
)
