# Configuration file

```@meta
CurrentModule = Dendro
```

The bands a finding is judged against are drawn from common complexity guidance. They are
deliberate opinions, and a project retunes them from a `.dendro.toml` at its repo root,
with no code changes.

Only the flagging opinions are configurable: the bands, the percentile cut, the clone
thresholds, which rules are active, which libraries a scan compares against, which
languages are registered, and which paths are left out of the scan. The corpus floors and
the model internals are not.

## The cascade

Discovery is a cascade, merged key by key, last wins:

1. the built-in defaults,
2. the pattern pack Dendro ships, `src/patterns/builtin.toml`,
3. a user-global `~/.config/dendro/config.toml` (`XDG_CONFIG_HOME` if set),
4. the repo `.dendro.toml`, found at the git toplevel of the scanned roots,
5. any explicit [`analyze`](@ref) keyword.

`--config=<file>` reads one file in place of discovery and `--no-config` ignores config
files entirely; both are described in [Command line](@ref). Neither drops the pack, which
is a default rather than a discovered layer. `[rules] <name> = false` is the lever for
turning one of its rules off, per rule and by name, and [Rules Dendro ships](@ref) holds
the rest of the recipe.

Layer 2 is read through the same walk the two file layers take, so nothing about the
shipped rules is a special case. A layer naming a rule an earlier one declared inherits
that declaration and overrides only the keys it sets, which is how a repo promotes a
shipped rule to `severity = "high"` in one line.

The query files cascade the same way and separately, per rule per language: the pack's
`src/patterns/`, then `~/.config/dendro/patterns/`, then the repo's `.dendro/patterns/`.
A repo query for one rule in one language shadows the shipped one for that pair alone.

The repo file is found once per run, not per subtree. One corpus means one baseline and
one set of bands, since the corpus-relative score is global and per-directory bands would
be incoherent with it.

## Bands, the cut, and which rules run

```toml
# .dendro.toml
cut = 0.97                 # percentile cutoff for corpus-relative flags

[bands]
cyclomatic = [15, 30]      # scalar metric: override (warn, high)
function_length = [60, 120]
low_cohesion = [5, 7]      # relational metric: override its band
back_edge = [90, 97]
dependency_cycle = [6, 12]

[rules]
npath = true               # enable an optional rule
parameter_count = false    # disable a built-in rule
```

`[bands]` keys are the scalar metric names plus the relational metrics that carry a
band, each taking a `[warn, high]` pair. [Metric reference](@ref) lists which names those
are and what each defaults to.

`[rules]` keys are any rule name, on or off. The opt-in passes are switched on here too.
Eight of them take a key: `reimplementation`, `incoherent_package`, `divisible_package`,
`child_count`, `distant_definition`, `divisible_class`, `library_duplicate`,
`library_near_duplicate`.

## Clone detection

```toml
[clones]
min_size = 12          # min named-node subtree to count as a clone
threshold = 0.9        # near-miss similarity cutoff
radius_factor = 0.5    # candidate-search radius, as a fraction of function size
```

The three cross-corpus keys live in the same table, since they are clone thresholds too:
`library_threshold`, `library_gate_coverage`, and `library_anchor_grain`, documented with
the values they were measured at under
[Duplication against a library](@ref).

## Report

The `[report]` table owns `base_summary`, which defaults to `true`. Set
`base_summary = false` to skip scoring the base corpus while retaining the current scores
and line delta. The text report then omits the base comparison columns.

## Tables owned by a feature

Four tables are the configuration surface of one feature each, and each is documented
where that feature is:

| Table | Declares | Read |
| --- | --- | --- |
| `[libraries.<name>]` | a reference corpus, by `path` or `paths` | [Comparing against a library](@ref) |
| `[reimplementation]` | the vocabulary-overlap cutoff | [Duplicate detection](@ref) |
| `[languages.<name>]` | a language to register, or a shipped query to replace | [Adding a language](@ref) |
| `[patterns.<name>]` | a project's own rule, realised by a query under `patterns_dir` | [Pattern rules](@ref) |

Three top-level keys those leave here. `patterns_dir` points at the directory holding the
pattern queries, resolved against the config file that set it, and defaults to
`.dendro/patterns` beside the config. `ignore` takes gitignore-style patterns that drop
paths before parsing, so a vendored or generated tree is neither flagged nor counted in
the baseline:

```toml
ignore = ["vendor/", "deps/**", "*.generated.jl"]
```

[Suppressing findings](@ref) covers the pattern syntax and why an excluded tree has to
leave the baseline too. [`analyze`](@ref)'s `ignore` keyword adds to this list rather
than replacing it.

## Files a generator wrote

`ignore` names paths. `generated` reads content: Dendro looks at the first 40 lines of
every file it is about to parse and turns away one carrying a generator's header or a
bundler's module runtime. A path pattern misses the checked-in bundle nobody thought to
list; this catches it. The built-in signatures are:

- the module runtime a bundler writes: `__webpack_require__` (webpack), `parcelRequire`
  (Parcel), `__toESM(` (esbuild)
- the header a generator writes at the top of what it emits: `<auto-generated`,
  `Generated by`, `@generated`, `DO NOT EDIT`

Name your own generator's header to add to that list:

```toml
generated = ["# Code generated by protoc"]
```

A scan warns once with the count and the first few paths, and the report closes with a
line naming how many files went and which signatures named them. Nothing is dropped
quietly.

Set the key to `false` to read every file:

```toml
generated = false
```

Reach for that when your own source discusses generated code near the top of a file, since
the key adds signatures to the built-in list and cannot take one out of it. Dendro's own
`.dendro.toml` sets `false`: `src/corpus.jl` declares the signatures, so it names a
bundler runtime in its own first lines.

## When a key is wrong

An unknown key warns and is ignored, so a typo is visible rather than silent and a file
written for a newer Dendro still applies the keys this version knows.

A library path matching nothing is the one exception and errors instead: a library
resolving to nothing would silently turn its gate off, which is the failure that feature
exists to prevent.
