# Reading Quarto documents and scripts

Status: accepted. The unit model, the rule scoping and the script half are
implemented; the Quarto half waits on a `TreeSitter.jl` release carrying
`src/injection.jl`.
Date: 2026-07-31

## The problem

Dendro reports per unit, and a unit is a callable definition. Package source is
mostly callable definitions, so that reading covers it. Scripts and Quarto
documents are not, and Dendro either measures a small fraction of them or cannot
open them at all.

Measured over an anonymised corpus of consulting analysis repositories (12
projects, 840 `.jl` files, 307 `.qmd` documents), against a package-source
reference of 8 registered Julia packages:

| corpus | code lines inside a function unit | files with no unit at all |
|---|---|---|
| package `src/` (184 files) | 76.0% | 11 of 184 |
| `docs/make.jl` (78 files) | 7.5% | 69 of 78 |
| `benchmark/`, `examples/` (213 files) | 53.5% (per-file median 7.7%) | 95 of 213 |
| analysis project `.jl` (440 files) | 15.9% | 271 of 440 |

A `.qmd` scores zero on that table because no extension maps to it. The 307
documents hold 6,446 fenced executable cells, 3,394 of them Julia, across 197
documents. In one project the entire analysis lives in 38 documents totalling
55,714 lines and three `.jl` files.

This has a second cost that is not about missing findings. Because the callers
live in documents Dendro cannot read, helper definitions read as dead. Across 7
projects Dendro reports 429 `:unreferenced` findings on the `.jl` sources alone;
127 of those names (29.6%, and 47.0% in the worst project) appear in a `.qmd` in
the same repository. Reading the documents removes false positives as well as
adding findings.

## What a unit is in a document, and what one is in a script

A Quarto cell is a boundary the author drew. A run of top-level statements in a
script is not. That distinction decides the whole design, and it is measurable.

Taking each Julia cell as one unit and scoring it with the existing rules and the
existing fixed bands:

| unit population | len≥50 | len≥100 | cyc≥11 | cyc≥21 | cog≥15 | cog≥25 | nest≥4 | nest≥6 |
|---|---|---|---|---|---|---|---|---|
| package functions (n=5232, the reference) | 4.2% | 1.1% | 5.9% | 1.3% | 5.3% | 2.1% | 3.0% | 0.4% |
| Quarto Julia cells (n=3386) | 5.3% | 1.3% | 1.9% | 0.4% | 1.0% | 0.1% | 0.0% | 0.0% |
| script top-level, one unit per file (n=779) | 79.8% | **56.4%** | 4.1% | 1.4% | 3.6% | 1.2% | 0.3% | 0.0% |
| script top-level, runs between definitions (n=1307) | 45.8% | **30.8%** | 2.4% | 0.8% | 2.1% | 0.5% | 0.2% | 0.0% |
| package top-level, runs between definitions (n=995) | 10.7% | 3.6% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |

A cell fires every band at or below the rate a package function does. It needs no
retuning and no new band. A script's top level fires every band at the reference
rate except length, which fires 28 to 51 times as often. One rule fails to
transfer, and it is the one that measures how far a boundary is from the boundary
before it. A cell has such a boundary because someone put it there. The rest of a
script does not.

So the rule is: length applies to a unit an author bounded. It does not apply to a
unit whose extent is "whatever else is in the file".

Top-level code is read as contiguous runs between definitions, not as one unit per
file. The diff scope reads a unit's line span, so a whole-file unit would report for
a change on any line in the file, including lines inside the definitions it
straddles. A module body counts as a container, since a package's main file is
otherwise one large declaration nothing reads: 24 of 184 package files wrap
everything that way, and an earlier version of the control below measured none of
their contents.

Sub-dividing a script does not rescue it. Splitting at banner comments still fires
length at 17.2%, and the convention is not there to split on: of 440 analysis
scripts, 0 use `# %%` cell markers, 99 use `# ---` and 73 use `# ===`, and they
disagree. Inventing a boundary would be a guess, where breaking at a definition is
something the language already says.

## Extraction

Follow Runic's `format_markdown` scan, which already solves this for the same file
types and is in use on the same corpus. Specifically its fence regexes including
the Quarto braced form, its exact-tick close rule at the opening indent, its
indent validation and byte-indexed stripping, its unclosed-fence rule, and its YAML
front-matter skip:

```julia
const re_fence_open = r"^(\h*)(`{3,})\h*(\{[^}]*\}|[A-Za-z0-9_-]*)"
const re_fence_braced_lang = r"^\{\h*([A-Za-z0-9_-]+)"
const re_front_matter_delim = r"^---\h*$"
```

Two deliberate departures. Runic reduces `{julia}` to `julia` because it formats
both; Dendro keeps the distinction and scans executable (braced) cells only, since
a display fence is documentation. That costs nothing: the corpus has 3,394
executable Julia cells and 13 display ones. Runic also treats four-space indented
blocks as Julia, which Documenter needs and Quarto never executes, so Dendro skips
them.

Two details the port must not lose.

Keep the indent handling in bytes on both sides: measure with
`ncodeunits(indent)`, slice with `line[(n + 1):end]`, and test membership with
`startswith(line, indent)` so nothing counts characters. Runic's fence path
already does exactly this and is correct; its one `chop(; head = n)` sits in the
indented-code path where the indent is four ASCII spaces and the branch has
already required the line to start with them, so it is a latent trap and not a
live bug, now pinned by a regression test at `03d00b1` using a genuine two-byte
NBSP. There is nothing to carry back to Runic. The warning is for this port,
because reimplementing the scan is what puts the trap back in reach.

And `fence_language` does not match a Pandoc raw block (`{=typst}`, 102 in the
corpus), so such a block keeps its braces and resolves to no language. That is the
behaviour wanted, so pin it with a test before it becomes an accident.

## Positioning

Do not build a tangled buffer. `TreeSitter.jl` has `set_included_ranges!` and
`ts_range` (committed on `main` in `src/injection.jl`, not in the released 0.2.3),
which parses selected ranges of the real source as one tree with byte and point
coordinates in the original document's space.

Verified on a document with front matter, prose, an `r` cell, a fenced div, and a
`#|` option line: nodes report at their true `.qmd` lines and columns, cells join
into one tree, and the tree carries no `ERROR` or `MISSING`. Against a blank-padded
tangle over all 307 documents, 47,142 code lines aligned and 0 misaligned, so
either approach is line-correct; injection is additionally column-correct, keeps
`ParsedFile.source` as the real file text so node slices and inline
`dendro-ignore` directives read the file, and avoids a second copy of every
document.

One trap, found by testing: each range must include its line terminator. Ranges
ending at the last code byte fuse consecutive lines into one statement and the
parse fills with `ERROR` and `MISSING`.

Ranges are emitted per line so `#|` option lines can be punched out.

Parse quality on the real corpus is 4 documents of 307 carrying any `ERROR` node,
8 nodes in total, and every one of them was traced to its cause. None is an
extraction defect: one document is a deliberate error fixture, one holds a literal
dangling `using` with no module name in an `archives/` directory, and the rest are
`~` inside a vector literal and a stray quote, which tree-sitter-julia does not
take. The extracted text matches the source line for line in all four.

## Entering the corpus

A `.qmd` is not a language, so it does not belong in `EXTENSIONS`, which maps an
extension to exactly one. Its languages are named by its cells, and only its cells
are code at all. That wants a second registry beside the first: an extension to a
container format, where a format says how to find the embedded code and nothing
about what language it is.

The rest follows the path an ordinary file already takes.

- `source_files` keeps a path whose extension resolves to a language *or* to a
  container, so a directory walk picks documents up with no new traversal.
- `collect_corpus` stops erroring on a named `.qmd`, since its language can now be
  inferred, from its content rather than its name.
- `parse_corpus` reads a container path by extracting its cells, grouping them by
  the language each fence names, resolving that name through the scan's profile
  registry, and parsing each group by injection. A cell language with no profile is
  skipped exactly as an unrecognised extension is.

`ParsedFile` needs no new field. Under injection `source` is the real document text
and `tree` covers only the cell ranges, so `language`, `profile`, `file` and
`directives` all mean what they already mean, and nothing downstream has to ask
whether a record came from a container. One consequence is deliberate: a document's
Julia cells sample into the Julia baseline alongside every `.jl` file, which is what
makes the percentile comparable and is the same reason the fixed bands transfer.

Documents are read by default. A `.qmd` in the tree is the project's code, and a
project that wants it out uses `ignore` as it would for anything else. This does
change what an existing scan of a mixed repository sees, which is the point.

An inline `dendro-ignore` is found through `index.comment`, so it works inside a
cell and cannot be written in prose. That is the right boundary: a directive
accepts a finding, and a finding is on code.

One `ParsedFile` per document, not per language, until file identity becomes
`(path, language)`. The measurement and the reason are under Deliberately not in
this.

## Two steps, and what each one buys

Reading a document is worth doing on its own, before cells become units.

A function defined inside a cell is an ordinary definition, so the moment Dendro can
open a `.qmd` it is a unit like any other, with every rule, both clone passes and
both library passes over it. More to the point, the cell code that is *not* a
definition still contributes references, and that is what retires the 429
`:unreferenced` findings above, 127 of them names a `.qmd` in the same repository
uses. None of this touches the unit model.

Cells as units is the separate step, and it is what the duplication numbers below
need. It does not fall out of injection for free. A document parses to one tree, so
its top-level code already becomes contiguous runs broken at definitions, the same
construction a script gets; making those runs stop at the fences instead means
passing the extractor's cell line ranges into unit construction. That is the whole
of the extra work, and it is why the two steps separate cleanly.

## Unit model

`FunctionUnit` holds one node. A cell and a script's top level are both a run of
sibling nodes under the tree root, and no node spans exactly that run. Generalise
the unit to carry a node run, with a callable being the run of one:

- `fold_unit`, `subtrees`, `token_stream`, and byte-range consumers fold over the
  run and combine, which they already do over children.
- `function_length`, `firstline`, `lastline` are already span readings.
- The unit's clone hash folds its members' hashes in order, as `collect_subtrees!`
  folds a node's children.

Every unit-keyed pass then picks cells and script top levels up with no further
change, because they all read `functions(index)`: the scalar and flag rules, both
clone passes, both library passes, naturalness, reimplementation, cohesion, and
the corpus graph.

Roughly a dozen call sites read `.node`; most of the twelve consumers read only
`.firstline`.

## Which rules run on a non-callable unit

Confirmed by measurement, not by judgement:

- Excluded, being about a signature: `parameter_count`, `return_count`,
  `unused_parameter`. `unused_parameter` is already inert here (10 findings in both
  views), so this is a statement of intent rather than a fix.
- Excluded on a file-level top-level unit, per the band table: `function_length`.
  It stays on for a cell, where it measures at the reference rate.
- `unused_local` must keep skipping top-level bindings. This is a confirmed
  blocker. It currently spares them only by `containing_unit` returning 0, and a
  top-level Julia assignment is kinded `:assign`, which is in `LOCAL_KINDS`. Give
  it a containing unit and it fires on every variable a cell produces for a later
  cell: 23 findings become 1,946 across the same corpus. It is a `:high` flag, so
  it sits in `errors()` and would make the gate unsatisfiable on day one. Its unit
  test must ask whether the unit is callable, as its own docstring already says
  ("A top-level binding is visible across files and belongs to `unreferenced`").
  `local_count` and `shadowed_variable` read the same substrate and need the same
  treatment.
- Everything else runs unchanged: `cyclomatic`, `cognitive_complexity`,
  `nesting_depth`, `boolean_complexity`, every remaining flag, and every corpus
  pass.

## Naming a unit, and the ratchet

`fkey` keys a finding by `(metric, sorted (file, unit) pairs)` and ignores line
numbers so the gate survives drift. A positional name ("cell 7") would break that:
inserting a cell renames every later one and the ratchet re-reports the file.

Name a cell by its `#| label:` when it has one (9.5% of cells), else the nearest
preceding markdown heading (83.9%), else empty (6.6%). Headings repeat within a
file 44.1% of the time, which is fine: `fkey` already collides for non-function
flags and the base floor is a multiset, so repeats are matched by count. A script's
file-level unit needs no name; it is the file.

## Expected findings

Within-project exact duplication, which today reports nothing for either file kind:

| population | whole-unit clusters | of which cross-file | block clusters | of which cross-file |
|---|---|---|---|---|
| Quarto cells, 11 projects, 3,291 cells | 278 | 165 | 241 | 178 |
| script top-level runs, 12 projects, 1,257 regions | 68 | 68 | 398 | 329 |
| package top-level runs, 184 files (control) | 6 | - | 2 | - |

The control matters: the mechanism is quiet on package source, so the volume on
analysis code is the code repeating itself and not a floor set too low. Raising the
floor confirms it. Cluster members run to a median of 92 named nodes, and lifting
the floor from 20 to 80 nodes only takes 278 clusters to 162.

Per-project counts are 0, 0, 4, 4, 7, 37, 39, 54, 84, 85, 205. A project adopting
this on an existing repository should use `errors(...; since = ref)`, the ratchet
that already exists, rather than expecting a clean floor.

**The library passes are not where this pays off, contrary to expectation.** Over
the same documents against each project's declared and locally resolvable
dependencies, `library_duplicate` yields 1 finding and `library_near_duplicate` 2,
whether cells are units or not. The same passes over the same projects' `.jl`
sources do fire (13, 8, 6, 2, 1 per project), so the pass works and the corpus is
simply not reimplementing its dependencies inside its documents; the duplication is
between one analysis and the next. Every one of those findings is `:warn`, none
`:high`. Caveat: dependency resolution here picked an arbitrary installed version
per package and covered registered dependencies only, so this measures the shape of
the answer and not its exact size.

## Scope and sequencing

1. Fenced-cell extraction and its tests, ported from Runic with the departures
   above. No Dendro integration yet.
2. Unit as a node run. Done: pure refactor, no behaviour change, since every
   existing unit is a run of one.
3. Rule applicability by unit kind, with the `unused_local` fix. Done.
4. `.qmd` as a container format in the corpus, on injection, per Entering the
   corpus. Needs a `TreeSitter.jl` release carrying `src/injection.jl`. Worth
   landing on its own, before cells are units: it needs no unit-model change and it
   is what retires the `:unreferenced` false positives.
5. Script top-level units. Done, and it is what forced `containing_callable`: making
   top-level code a unit fed it into the passes that ask where a definition belongs,
   and `:low_cohesion` fired on nearly every file in Dendro's own `src`.
6. Cells as units, by passing the extractor's cell ranges into unit construction.

Steps 2, 3 and 5 landed before 4 so the unit-model change and the new file type
review apart. Steps 4 and 6 are what is left, and 4 is worth shipping without 6.

## Deliberately not in this

- `.ipynb`. It is JSON, so it needs a different extractor and a different line
  model. `.Rmd` and `.md` share this design and are cheap to add after.
- R as a scanned language. `tree_sitter_r_jll` exists and 76 documents in the
  corpus are R, which makes it worth doing and separable from this.
- More than one scanned language per document. 3.4% of documents mix Julia and R
  cells, and today that is free, because Dendro reads neither `.qmd` nor R. Adding
  R would make it a collision: several passes key a `Dict{String, ...}` on
  `f.file`, so two `ParsedFile`s sharing a path would silently overwrite. Whichever
  of the two lands second has to make file identity `(path, language)` or refuse
  the second language and say so.

## Not measured

- Injection cost at corpus scale. The tangled path parsed 307 documents in 4.5
  seconds, so the shape is fine, but injection itself was verified for correctness
  and not timed.
- Whether `--base` diff scoping behaves on a document. It should, because
  `changed_ranges` reads the `.qmd`'s own line numbers and injection preserves
  them, but it has not been run.
