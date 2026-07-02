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

## Reimplementation candidates

Both structural passes miss the rewrite: a helper reimplemented with different
structure, a loop against straight-line code, shares no subtree shape with the
original. It usually keeps the vocabulary, the same callees and the same domain
words in its identifiers, and that is what the `:reimplementation` pass reads. Each
function is fingerprinted by its callee names plus the word fragments of its
identifiers, every term weighted by rarity in the scanned corpus (IDF, rebuilt on
each scan). Two functions pair when the rare vocabulary they share outweighs the
rest of their combined vocabulary, the finding's value that overlap as a percent:

```
src/fetch.jl:12  fetch_once  reimplementation 74 (high)
    also at src/retry.jl:30  fetch_with_retry
```

The evidence is vocabulary, not structure, so the finding is a proposal: two
functions that talk about the same things in different shapes. The pass is off by
default and opts in through a `.dendro.toml`:

```toml
[rules]
reimplementation = true

[reimplementation]
threshold = 0.6   # overlap a pair must reach, the one knob
```

Four gates keep the proposals worth reading. A pair the clone passes already
report is theirs, never repeated here. A pair where one function calls the other
by name is a caller and its helper, not a rewrite. Same-named functions never
pair, since overloads and interface implementations share vocabulary
legitimately. And a pair whose sizes differ beyond a 2:1 ratio is a fragment
against a whole. Deliberately parallel families still pair, per-language
implementations of one operation are vocabulary twins by design, so expect a
codebase with such families to surface them; suppress with
`dendro-ignore: reimplementation` where they are intended.

The pass stays name-based and corpus-derived, like the rest of Dendro: no types,
no call graph, no pretrained model. A rewrite that also renames the domain
vocabulary stays invisible to it.
