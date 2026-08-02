# Command line

```@meta
CurrentModule = Dendro
```

`julia -m Dendro <path>...` runs the same analysis from a shell, in an environment where
Dendro and the grammars it needs are installed. Installed as an app, it is the `dendro`
command.

```bash
julia -m Dendro src                       # report the findings
julia -m Dendro --base=origin/main src    # only the lines a change touched
julia -m Dendro --check src               # exit 1 on any error-severity finding (CI gate)
julia -m Dendro --format=github src       # GitHub Actions annotations
julia -m Dendro --library=IterTools=../IterTools/src src   # duplication against a library
```

The default report ranks every function by percentile, so it is never empty, the triage
view. `--check` instead gates on the `:high` floor, the error-severity findings, so a
clean codebase exits 0 and a regression exits 1. That is the [Gating CI](@ref) floor read
from a shell.

`--check` alone reports every error-severity finding in the tree, so a codebase that is
not yet clean fails from the first run. `--since=<ref>` makes it the ratchet instead:
that floor minus what the ref already reported, so only what a change introduced fails
the build. It is the [`errors`](@ref) keyword of the same name.

```bash
dendro --check --since=origin/main src
```

`--base` asks a different question, scoping the report to the lines a change touched, so
naming both is a usage error rather than a silent choice of one.

Both read the repository through libgit2 rather than by running `git`, so neither needs
the `git` or `tar` binaries on `PATH`. That matters in a minimal CI container, and it
means the base revision is read straight from the object database: no worktree is
touched and no index is mutated. One consequence is worth knowing if your repository
uses `export-ignore` gitattributes, which `git archive` would honour and a direct read of
the tree does not. The base corpus is now the same set of files the working tree is
scanned as, which is the comparison a ratchet wants; an `export-ignore`d file that used
to be missing from the base alone would have read as newly added.

## Flags

```
--base=<ref>          report only findings on lines changed against <ref>
--since=<ref>         report only error-severity findings <ref> did not already have
--config=<file>       read <file> instead of a discovered .dendro.toml
--no-config           ignore .dendro.toml, score against built-in defaults
--cut=<float>         percentile cutoff for corpus-relative flags (default 0.95)
--library=<path>      index <path> as a library to report duplication against
--library=<name>=<path>
--format=<fmt>        output format: text (default) or github
--check               exit 1 on any error-severity finding
--check-patterns      check pattern rules against their fixtures and exit
--version             print version and exit
--help, -h            print this message and exit
```

`--library` is repeatable and merges with whatever the config declares; see
[Comparing against a library](@ref) for the recipe that generates one flag per
dependency. `--check-patterns` runs the fixture check described in
[Pattern rules](@ref).

A bad flag, a missing value, or a `--library` path that does not exist is a usage error
rather than a silent clean run.

## Threads

Analysis parallelises across threads on a large corpus. Start Julia with `-t auto` (or
`-tN`, or set `JULIA_NUM_THREADS`) and the parsing, scoring, duplicate, and cross-file
passes fan out over the available threads.

```bash
julia -t auto -m Dendro src
```

Each pass falls back to serial below a small size floor on its own item count (files,
clone pairs, functions), or single-threaded, so a small diff or a single-file gate pays
little to no overhead. The findings are identical whatever the thread count.

The same holds for [`analyze`](@ref) called from Julia: threading is a property of the
session, not a keyword.
