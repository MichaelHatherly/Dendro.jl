# Comparing against a library

```@meta
CurrentModule = Dendro
```

Point Dendro at the source of a dependency and it reports where your code duplicates it.
[Duplication against a library](@ref) explains what the two passes read and why only one
of them gates; this page is how to run one.

## Running a scan

```julia
using Dendro: analyze, Library

analyze("src"; libraries = [Library("IterTools", "~/.julia/packages/IterTools/A1b2C/src")])
analyze("src"; libraries = ["../shared/src"])   # a bare path is one root, named after it
```

Absent `libraries` in both the config and the keyword, neither pass runs and the scan
costs nothing. There is nothing to switch on, only something to point at.

## Declaring libraries in `.dendro.toml`

Declare libraries where a project declares everything else:

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
warns and is dropped. [Duplication against a library](@ref) records the measurements each
default came from.

## From the command line

`--library`, listed among the flags under [Command line](@ref), is repeatable and merges
with whatever the config declares. Its value splits on its first `=`, so a Windows path
keeps its drive letter.

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
it is for every other rule. See [Gating CI](@ref).

## What it costs

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
