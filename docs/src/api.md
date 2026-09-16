# API reference

Dendro exports nothing. Its public API is marked with the `public` keyword. Import
what you call, or qualify with `Dendro.`.

```@meta
CurrentModule = Dendro
```

## Analysis

```@docs
analyze
active
github_annotations
```

[`mermaid`](@ref) is documented with the graphs it draws, under [Diagrams](@ref).

## Gating

```@docs
errors
```

## Findings

```@docs
Finding
Findings
Location
GeneratedFile
```

## Corpus summary

What a scan measured about its corpus as a whole, reached through `Findings.summary`. See
[Corpus scores](@ref) for what the two ratios mean.

```@docs
ScanSummary
CorpusScores
LineDelta
```

## Rules

```@docs
Rule
BUILTIN_RULES
OPTIONAL_RULES
```

## Pattern rule types

```@docs
PatternSpec
check_patterns
PatternTestFailure
```

## Configuration

```@docs
Config
Library
```
