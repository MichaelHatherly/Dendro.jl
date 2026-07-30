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

A library is a **reference corpus**: source Dendro reads and never scores. It stays out of
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

Evidence lives in the label rather than in a second location, and that is load-bearing
twice over. A `Location` pointing outside the scanned corpus would throw under
`analyze(; base)`, the diff-scoped view. And the gate's ratchet keys a finding by its
locations, so a library path, version slug and all, would rewrite that key on every
dependency upgrade. Neither happens.

The value is **coverage**: how much of your enclosing function the matched region is, as a
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

Only the first row reaches [`errors`](@ref) and the CI ratchet, and the two facts in it are
only actionable together. A match against a public whole function is importable: there is a
name to call instead. A private one is not, though it still says the library solved this and
you solved it again, which usually means the abstraction belongs somewhere neither corpus
has it yet. And you cannot import half a function, however public the function containing
it, so a block match names the containing symbol and leaves the decision to you.

`library_gate_coverage` defaults to 50. Below half, "import this instead" is an edit inside
a function you keep rather than a deletion, which is a suggestion and not a violation.

Publicness is read per language from declared exports or a visibility modifier, the same
reading `:unreferenced` uses, with one default inverted. A library in a language Dendro has
no linkage model for reads as **private**, so every match from it warns and nothing gates.
`:unreferenced` reads the same case as public, because there the safe direction is not
calling an unverifiable definition dead; here public is what promotes a finding into the
gate, so the safe direction is the other one.

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
library_threshold     = 0.85   # near-miss match cutoff
library_gate_coverage = 50     # coverage a public whole-unit match needs for :high

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

Approximate partial containment, a library function's shape appearing edited inside a much
larger function of yours, is found when it is exact and not otherwise. The size banding is
what keeps the near pass off a full pairwise comparison, and lifting it needs the near pass
run at anchor granularity on both sides. The mechanism is known; the cost on a real
dependency set is not, so it is not shipped.
