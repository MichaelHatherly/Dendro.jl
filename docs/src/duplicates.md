# Duplicate detection

```@meta
CurrentModule = Dendro
```

[`analyze`](@ref) reports duplicates as part of a full analysis: code duplicated
across the corpus, including across different files. It hashes each subtree by its
structure, type not text, so fragments that differ only in variable names or
literal values still match (Type-2 clones). It catches the copy-paste-then-rename
that generated code produces. Detection works at two scales from the same
mechanism: a whole function duplicated, or one block, an `if` or loop body, copied
between functions that otherwise differ. A maximality filter keeps only the largest
clone, so a duplicated function is reported once, not again for every block inside
it. Each cluster of two or more comes back as one `:duplicate` finding whose
`locations` list every member:

```
src/a.jl:10  parse_header  duplicate 3 (high)
    also at src/b.jl:42  read_header
    also at src/c.jl:7  load_header
```

`min_size` (default 10 named nodes) gates out trivial functions, so one-line
getters do not cluster. Blocks must clear twice that, since a short block of
boilerplate coincides across unrelated code while a small whole function is already
a meaningful unit. Pass `min_size` lower to widen the net, higher to focus on large
clones.

## Near-misses

Exact clustering misses the copy-paste-then-edit: two functions identical but for
an added or removed statement hash differently and never meet. [`analyze`](@ref)
also reports these as `:near_duplicate`. It compares each function's pre-order
sequence of subtree hashes by longest common subsequence, after NiCad, scoring
similarity as `|LCS| / max(|a|, |b|)`, so functions that are close but not identical
cluster when they clear the `threshold` (default 0.85). The LCS is order-aware where
a multiset overlap is not: a reordering of the same statements, or a small fragment
matching inside a large function, scores low and is rejected. A characteristic-vector
radius query (DECKARD-style), banded by function size, finds candidate pairs without
comparing every pair; the LCS similarity confirms each one. The finding's value is
the cluster's weakest pairwise similarity as a percent:

```
src/parser.jl:40  read_header  near_duplicate 88 (high)
    also at src/loader.jl:12  load_header
```

A near-miss stays syntactic and within one language, like exact detection. Pass
`threshold` higher to demand closer matches, `radius_factor` to widen or narrow the
candidate search.
