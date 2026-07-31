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

```julia
using Dendro: analyze, Library

analyze("src"; libraries = [Library("IterTools", "~/.julia/packages/IterTools/A1b2C/src")])
analyze("src"; libraries = ["../shared/src"])   # a bare path is one root, named after it
```

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

## Configuration

Declare libraries where a project declares everything else, in `.dendro.toml`:

```toml
[libraries.IterTools]
path = "~/.julia/packages/IterTools/*/src"

[libraries.Base]
path = "/usr/local/julia/base"
ignore = ["precompile.jl"]

[libraries.Internal]
paths = ["../shared/src", "../shared/ext"]

[clones]
library_threshold     = 0.90   # near-miss match cutoff
library_gate_coverage = 50     # coverage a public whole-unit match needs for :high
library_anchor_grain  = true   # compare blocks too, not just whole functions

[rules]
library_near_duplicate = false  # keep the exact pass, drop the near one
```

`path` or `paths`, at least one required. Relative paths resolve against the config file's
own directory, `~` expands, and a single `*` per path component expands as a filesystem
glob, which is what makes `~/.julia/packages/IterTools/*/src` survive a version bump. `**`
is refused: one `*` covers the version-slug case, and recursive globbing over a package
depot is a way to index gigabytes by accident.

A path that matches nothing is an error, not a warning, where an unknown key inside the
same table warns and is dropped. The asymmetry is deliberate: a typo'd key leaves the rest
of the table working, whereas a path resolving to nothing silently turns the gate off,
which is the failure this whole feature exists to prevent. The same reasoning makes a
`--library` path that does not exist a usage error.

The thresholds live in `[clones]` rather than a table of their own. They are
clone-detection thresholds, and a `[library]` table one letter from `[libraries]` is
exactly the typo that would silently discard a setting, since an unknown top-level key
warns and is dropped.

Absent `libraries` in both the config and the keyword, neither pass runs and the scan costs
nothing. There is nothing to switch on, only something to point at.

## Cost

Indexing the libraries is the dominant term and scales with their source size, not with
your project's. Measured cold on six projects with 40 to 360 dependency source files:
0.3 to 1.5 seconds to index, and 0.8 to 3.8 seconds for a whole scan. The exact join is one
dictionary lookup per project anchor, so it is independent of how large the libraries are,
which is what lets it gate.

Indexing memoizes to disk in a scratch space Dendro owns, keyed by the index format, the
Dendro and Julia versions, `min_size`, the grain, the size and mtime of every file indexed,
and the query files of each language among them. A dependency set changes rarely, so a warm
cache turns that 0.3–1.5 seconds into 0.06–0.15. Any load failure at all (a stale format, a
truncated write, a file another tool left there) is a miss and a rebuild. A cache is an
optimisation and must not be able to break a scan, so there is no error path from it.

The queries are in the key because they decide what an anchor is. Retune one with
`[languages.julia] queries` and the set of files indexed does not change, so without them
the key would not move and you would be served an index built against the query you
replaced.

Entries are written in a format Dendro defines rather than through Julia's `Serialization`.
`Serialization` rebuilds whatever types a stream names, which makes reading an entry someone
else wrote a way to run their code; the reader here names no type and allocates nothing from
a length it has not checked against the bytes in front of it. That matters if you share a
cache directory between CI jobs, which is the usual way to keep one warm.

Set `DENDRO_CACHE_DIR` to put the indices somewhere else, on a machine whose depot sits on
a disk that cannot hold them. It is an environment variable and not a `.dendro.toml` key
because the config file carries opinions about your code, not paths on your machine. Point
it at a directory Dendro owns: collection deletes entries by name, and while it only ever
removes names that look like its own hex digests, a directory you also keep other things in
is not what it is for.

An entry no scan has used for a week is deleted, swept when a new index is written and at
most once a day. This matters more than it sounds: the cache key includes each indexed
file's size and mtime, so upgrading a dependency does not overwrite its entry, it writes a
new one beside it. Without collection the space would grow for as long as your dependencies
keep moving. Scratch spaces are reclaimed by `Pkg.gc()` only once the owning package is
uninstalled, which is too late to be the answer here.

To clear the lot by hand:

```julia
using Scratch, Dendro
Scratch.clear_scratchspaces!(Dendro)
```

## From the command line

```
--library=<path>              index <path> as a library, named after its root
--library=<name>=<path>       ... under the display name <name>
```

Repeatable, and merged with whatever the config declares. The value splits on its first
`=`, so a Windows path keeps its drive letter.

Turning "my dependencies" into a list of source directories is per-ecosystem policy, and a
tool that reads a dozen grammars should not carry one language's package manager. So the
workflow generates the paths. For a Julia project:

```yaml
- name: Resolve dependency sources
  run: |
    julia --project=. -e '
      using Pkg
      open("dendro-libs.txt", "w") do io
          for (_, p) in Pkg.dependencies()
              p.is_direct_dep || continue
              src = joinpath(p.source, "src")
              isdir(src) && println(io, "--library=", p.name, "=", src)
          end
      end'

- name: Dendro
  run: |
    mapfile -t LIBS < dendro-libs.txt
    dendro --check --format=github "${LIBS[@]}" src
```

`mapfile` and the quoted expansion rather than `$(cat ...)`: a depot under a home directory
with a space in it would otherwise word-split into flags naming nothing, and a `--library`
naming nothing is the silent clean run this design refuses.

Direct dependencies only. Indexing the transitive closure finds matches against packages
the project cannot import without adding a dependency, which is a different and much weaker
finding. Dendro has no way to tell the two apart, so the recipe draws the line rather than
the tool.

## The gate and the ratchet

```julia
Dendro.errors("src"; libraries = [...], since = "origin/main")
```

Nothing in the ratchet key mentions a library, which has three consequences, each a
decision rather than a side effect. Upgrading a dependency never re-reports an unchanged
finding. Upgrading a dependency *can* introduce one, when the library grows a function you
already wrote, and that reads as new, which is right: something you should now import did
not exist before. And the base revision is scored against the libraries as they are on disk
now, so the ratchet holds them fixed and asks what your change did.

Turning the pass on cold will produce findings. `since` is what makes that survivable, as
it is for every other rule.

## When the finding is wrong

Answer with a suppression, not by arguing with the tool. `dendro-ignore: library_duplicate`
on the site's line, read exactly as `:duplicate` is; the finding stays counted and visible.

```julia
# dendro-ignore: library_duplicate -- LICENCE forbids taking the dependency
function chunk_by(xs, n)
```

The cases worth recognising:

- **Interface boilerplate.** `Base.show`, iteration protocol methods, table glue. Two
  packages implement the same protocol the same way because the protocol says to. The
  doubled floor for control-free functions removes the smallest of these.
- **Your project is a fork of, or an ancestor of, the library.** Every function matches.
  A `dendro-ignore-file`, or drop the library from the config.
- **Deliberate avoidance.** A licence, a heavy dependency being trimmed, a hot path where
  the library's generality costs too much. Suppress with the reason in the comment, which
  is what an inline directive is for.
- **Test helpers.** Pointing a library at its `test/` finds fixture builders everywhere.
  Configure `src` only, and `ignore` for the rest.
- **Generated code.** Both corpora generated from the same schema. `ignore` patterns, the
  same answer whole-corpus scanning already gives.
- **Overlap with `:duplicate`.** Two copies in your code of something a library also has
  fires `:duplicate` once over the cluster and `:library_duplicate` at each site. Both
  stay: they name different edits, unify the two copies, or delete both and import.

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
