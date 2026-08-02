using Documenter
using Dendro

makedocs(;
    modules = [Dendro],
    sitename = "Dendro.jl",
    authors = "Michael Hatherly",
    pages = [
        "Home" => "index.md",
        "Scoring and metrics" => "metrics.md",
        "Metric reference" => "metric-reference.md",
        "Duplicate detection" => "duplicates.md",
        "Duplication against a library" => "libraries.md",
        "Cohesion and placement" => "cohesion.md",
        "Diagrams" => "diagrams.md",
        "Gating CI" => "gating.md",
        "Command line" => "cli.md",
        "Configuration" => "configuration.md",
        "Suppressing findings" => "suppression.md",
        "Custom rules" => "rules.md",
        "Pattern rules" => "patterns.md",
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
