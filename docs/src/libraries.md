# Duplication against a library

```@meta
CurrentModule = Dendro
```

Every other reading Dendro makes is one corpus judged against itself: is this function
long, is this shape written twice here, does this unit belong in that file. This one is
asked against code the project does not own.

> Has the author written something a library they already ship with does for them?

A generated diff adds a 40-line `chunk_by` helper; the project already depends on a package
exporting exactly that; nothing complains. Point Dendro at the dependency's source and it
complains at the site in the project, naming the library symbol to import.
[Comparing against a library](@ref) is how to point it.

A library is a reference corpus: source Dendro reads and never scores. It stays out of
the baseline, out of the symbol resolution of your code, out of both graphs, out of the
per-file rules, and out of the corpus a diff scope is built over. So a dependency ten times
the size of your project neither moves your percentile scores nor fills the report with
findings about code nobody on your team can edit.

Two metrics, mirroring the within-corpus pair:

- `:library_duplicate`, an exact structural match against a library anchor.
- `:library_near_duplicate`, an approximate match against a library function.

They read differently. An exact match against a public function is "delete this and import
it"; a 0.87 match is "the library does nearly this, check the difference".

## What a finding says

One location, always in your code, with every library fact in the label:

```
src/util.jl:42  chunk_by  [IterTools.partition public, src/IterTools.jl:88]  library_duplicate 100 (high)
src/parse.jl:210  read_header  [HTTP.parse_line internal, src/parse.jl:44]  library_duplicate 34 (warn)
src/text.jl:12  squeeze  [Base.replace public, strings/util.jl:640; +2 more]  library_near_duplicate 91 (warn)
```

The label names the library-qualified symbol, whether it is part of that library's public
API, and where it sits relative to the library's own root. Up to three references are
named, best first, with a count for the rest.

Evidence lives in the label rather than in a second location, and two things break if it
does not. A `Location` pointing outside the scanned corpus would throw under
`analyze(; base)`, the diff-scoped view. And the gate's ratchet keys a finding by its
locations, so a library path, version slug and all, would rewrite that key on every
dependency upgrade. Neither happens.

The value is coverage: how much of your enclosing function the matched region is, as a
percent. Your whole 30-node function matching a library's 200-node function scores 100, the
strongest reading, because all of what you wrote is already there. A 30-node block inside
your 200-node function scores 15, a real finding ranked below it. One number, monotone in
how much code the edit deletes.

## What gates and what only warns

| the library side | coverage | band |
| --- | --- | --- |
| public whole function | at or above `library_gate_coverage` | `:high` |
| public whole function | below it | `:warn` |
| private whole function | any | `:warn` |
| a block inside a function | any | `:warn` |

That table is the exact pass. `:library_near_duplicate` always reports `:warn`, so it
never reaches [`errors`](@ref); see "How the defaults were set" below for why.

Only the first row reaches the gate and the CI ratchet, and the two facts in it are
only actionable together. A match against a public whole function is importable: there is a
name to call instead. A private one is not, though it still says the library solved this and
you solved it again, which usually means the abstraction belongs somewhere neither corpus
has it yet. And you cannot import half a function, however public the function containing
it, so a block match names the containing symbol and leaves the decision to you.

`library_gate_coverage` defaults to 50. Below half, "import this instead" is an edit inside
a function you keep rather than a deletion, which is a suggestion and not a violation.

Publicness is read per language from declared exports or a visibility modifier, the same
reading `:unreferenced` uses, with one default inverted. A library in a language Dendro has
no linkage model for reads as private, so every match from it warns and nothing gates.
`:unreferenced` reads the same case as public, because there the safe direction is not
calling an unverifiable definition dead; here public is what promotes a finding into the
gate, so the safe direction is the other one.

A match is attributed to the top-level definition enclosing it, and that is where the
publicness reading has a real ceiling. In a language whose methods live inside an `impl` or
class body, most functions are not top-level definitions, so a match inside one attributes
to nothing and reads as private. Measured on four Rust crates against their registry
sources, every finding came back `:warn` for exactly this reason: globset declares 45
top-level definitions against 147 function units. The gate is silent there rather than
wrong, which is the direction to fail in, but do not read a clean `errors` run on such a
project as evidence that the exact pass found nothing.

## Partial duplication

The library side indexes every anchor, whole functions and the blocks inside them, at the
same size floors exact clone detection already sets. Your side is walked the same way, so
partial duplication falls out with no extra mechanism: a block of yours matches a block of
theirs when twenty lines of your sixty-line function are what their helper does. A
maximality filter keeps the largest redundant region, so a duplicated whole function is not
also reported for each block inside it.

The floors carry over unchanged. A function with control flow clears `min_size`; a
control-free function and a block clear twice that. Genuinely useful small helpers
(`isblank(c) = c == ' ' || c == '\t'`) sit below the floor and will not be found. That is
the same bargain the clone passes make: a short control-free shape coincides across
unrelated code, and reporting it is noise.

The near pass compares whole functions on both sides by default, so a library function that
appears inside a much larger function of yours, edited, is not proposed: the two land in
size bands too far apart for the candidate query to pair them. `library_anchor_grain`
widens it to compare every anchor, which finds that case. It costs three to four times the
candidate pairs and three and a half to five times the confirmation work, measured across
five projects, for four to twenty percent more findings in a pass that never gates, so it
is off by default.

## How the defaults were set

None of these numbers is a guess. Ten Julia projects were scanned against their declared
direct dependencies at `min_size` 10: 7,208 project units against 559 to 6,067 library
units each.

The exact pass produced 74 findings, 3 of them `:high`. Hand classification of those three:
one true positive (`Documenter._escapeuri` against `URIs.escapeuri`, a genuine vendoring),
and two false positives, both short-form one-liners whose type annotations pushed them over
the control-free size floor. Zero to two gate findings per project is a satisfiable gate,
and the false positives take one suppression line each.

The near pass is where the interesting result is. At the originally proposed cutoff it
produced 618 findings, 84 of which would have gated: eight gate errors in a healthy
project, which is not a gate. Hand classification at its best cutoff put precision on those
findings at 11%, against the exact pass's 33%. Raising the cutoff does not help: it thins
the population and discards the true positives before the coincidences. So the near pass is
capped at `:warn` and never gates.

The mechanism behind that gap is worth knowing, because it is a consequence of the design
rather than a bug. The cross-corpus match test is `max(|LCS|/|a|, |LCS|/|r|)`, which is
`|LCS|` measured against the *shorter* side, where the within-corpus near pass measures
against the longer. That is deliberate, since a library function almost wholly contained in
one of yours is the finding as much as the other way round, but it is a far weaker test,
and it runs against a pool of thousands of library units rather than hundreds of your own.
Weaker test, more candidates, more coincidences.

`library_threshold` moved from the proposed 0.85 to 0.90 on the same evidence. There is no
measured gap to sit in: the population decays smoothly, 618 findings at 0.85, 207 at 0.90,
51 at 0.95, none at 0.98. 0.90 is a stated trade, the last cutoff that keeps the measured
true positives while cutting the noise by two thirds.

`library_gate_coverage` stayed at 50. It demotes five exact findings that would otherwise
gate, four of them false positives, which lifts precision on the gated population from
about 20% to 33%.

Four Rust crates were scanned against their registry sources as a check on the other
publicness path, a `pub` modifier rather than an export list. Nothing gated, for the
attribution reason above rather than anything about the predicate. What the Rust run did
confirm is the interface-boilerplate class: ripgrep's `printer` reports six exact matches
at full coverage against `termcolor`, every one a trait method (`set_color`, `reset`,
`flush`) implemented the way the trait says to.

## What it does not do

The passes read subtree hashes and tree shape, never types and never dispatch, the same
bargain the rest of Dendro makes. A helper rewritten with a different shape shares no
subtrees with the library function it duplicates and neither pass sees it; that is what
`:reimplementation` reads within one corpus, and it does not port across corpora as-is.

A rewrite that also renames the domain vocabulary is invisible to everything here, as it is
to `:reimplementation`.

And the gate rests on a publicness reading that is narrower than importability. Julia reads
the `export`/`public` lists, so a function reachable as `Foo.bar` but never exported counts
as internal and lands at `:warn`. The pass under-promotes on Julia rather than
over-promoting, which is the right direction for something a build fails on.
