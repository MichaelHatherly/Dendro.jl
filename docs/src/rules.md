# Custom rules

```@meta
CurrentModule = Dendro
```

A rule is a [`Rule`](@ref): a metric name, its kind (`:scalar` or `:flag`), a `(warn,
high)` band for scalars, and a function that measures one unit or the file's index.
The defaults live in [`BUILTIN_RULES`](@ref); pass `rules` to [`analyze`](@ref) to
extend them.

```julia
using Dendro: analyze, Rule, BUILTIN_RULES

# A flag rule reports one finding per node it returns from (index). The index's
# concepts are the nodes the language query tagged. This one flags comments carrying
# a BUG marker.
bug_markers(index) =
    [n for n in index.comment.nodes if occursin("BUG", TreeSitter.slice(index.source, n))]

analyze("src"; rules = [BUILTIN_RULES; Rule(:bug_marker, :flag, nothing, bug_markers)])
```

A scalar rule's function is `(unit, index) -> Int`; its value is scored against the
band and the corpus percentile like any built-in. A rule reads nodes through the
index's concepts, never a node-type string, so one definition works across languages.

[`OPTIONAL_RULES`](@ref) holds the rules that are off by default. Their bands are in
[Metric reference](@ref); what follows is what each measures and why it waits to be
asked for.

- `return_count`, return points per function. Wants per-project band tuning.
- `trivial_wrapper`, a function whose body is one delegating call. Higher
  false-positive rate than the flags that ship on.
- `unreachable_after_jump`, one finding per block holding a statement after an
  unconditional `return`, `break`, or `throw`.
- `npath`, NPath complexity after Nejmeh's measure as PMD computes it: sequences
  multiply, branches add, and each `&&`/`||` in a condition adds a path. It catches the
  sequential-branch explosion cyclomatic and cognitive complexity rate as moderate. The
  band wants per-project tuning, and the count grows multiplicatively, so it saturates
  rather than overflowing. Not wired for Ruby or Bash, whose branch bodies are not block
  nodes.
- `local_count`, distinct local names bound in a function with rebindings counted once,
  after pylint's too-many-locals. Wants per-project band tuning.
- `shadowed_variable`, a fresh local binding hiding an enclosing one. A Julia statement
  assignment in a nested scope rebinds rather than shadows and never reports, but a
  method local matching a class attribute does, an idiom some codebases use routinely.
- `fan_out`, distinct callables a function invokes, by called name with a member call
  counted by its final name. The band sits at the p95/p99 of a six-corpus calibration,
  and no fixed band separates a smell from a legitimate orchestrator: idiomatic corpora
  run p99 anywhere from 9 to 26.

Opt in with `analyze(path; rules = [BUILTIN_RULES; OPTIONAL_RULES])`, or by name in a
`.dendro.toml`.
