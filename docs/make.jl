using Documenter
using Dendro

makedocs(;
    modules = [Dendro],
    sitename = "Dendro.jl",
    authors = "Michael Hatherly",
    pages = [
        "Home" => "index.md",
        "Your first scan" => "tutorial.md",
        "Guides" => [
            "Gating CI" => "gating.md",
            "Suppressing findings" => "suppression.md",
            "Comparing against a library" => "libraries-howto.md",
            "Pattern rules" => "patterns.md",
            "Custom rules" => "rules.md",
            "Adding a language" => "languages-add.md",
            "Diagrams" => "diagrams.md",
        ],
        "Reference" => [
            "Metric reference" => "metric-reference.md",
            "Command line" => "cli.md",
            "Configuration file" => "configuration.md",
            "Pattern query syntax" => "pattern-syntax.md",
            "Languages and limitations" => "languages.md",
            "API reference" => "api.md",
        ],
        "How Dendro reads code" => [
            "Scoring and metrics" => "metrics.md",
            "Duplicate detection" => "duplicates.md",
            "Duplication against a library" => "libraries.md",
            "Cohesion and placement" => "cohesion.md",
            "Dependencies and layout" => "dependencies.md",
        ],
    ],
    checkdocs = :public,
    warnonly = false,
)

deploydocs(;
    repo = "github.com/MichaelHatherly/Dendro.jl",
    push_preview = true,
)
