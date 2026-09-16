# Rules Dendro ships

```@meta
CurrentModule = Dendro
```

Dendro ships eighteen pattern rules, declared in `src/patterns/builtin.toml` and realised
per grammar in `src/patterns/<lang>.patterns.scm`. They are on in every scan, need no
configuration, and answer the same question the rest of the tool does: where should a
reviewer look. They name the shapes that survive a working test suite, so nothing else
complains about them.

Every one of them is an ordinary pattern rule. [Pattern rules](@ref) describes the
mechanism and [Pattern query syntax](@ref) the query language; this page is the catalogue
and the recipe for changing one.

## The pack cannot fail your build

Each of the fifteen flag rules ships at `severity = "warn"`, which keeps it out of
[`errors`](@ref), the `:high` floor a project gates its own tests on. Nobody asked Dendro
for a style opinion that arrives as a build failure in their own repository. The rules
report, rank, and stay out of the way.

Each also ships with `guard = true`, for an unrelated reason. A guard is exempt from the
"matched nothing" report, which exists to catch a query naming a node type the grammar
never produces. These rules name shapes a healthy codebase does not contain, so without
the declaration a clean scan would print fifteen rules as broken.

The three density scalars are the exception to "all warn". `severity` says nothing about a
scalar: a scalar gates at its own `high` band, so these three can reach the floor. Their
bands are measured over 22837 callables in nine corpora, and each `high` edge clears the
worst function in all of them, so an extreme outlier is what it takes to trip one.

## Flag rules

| rule | what it names |
| --- | --- |
| `banner_comment` | a rule of dashes is decoration; the structure is already in the code |
| `boolean_return` | `if c: return True else: return False` is `return c` written out |
| `unreachable_branch` | a branch repeating an earlier condition can never run |
| `manual_min_max` | comparing two values to pick the larger is `max` |
| `swallowed_error` | a handler whose body only returns a constant discards the error it caught |
| `boolean_equality` | comparing against a boolean literal asks a question the value already answers |
| `empty_check` | comparing a length against zero asks a count where emptiness is the question |
| `redundant_conversion` | a value converted and immediately converted back |
| `redundant_keys` | asking a key view for membership when the container answers directly |
| `redundant_collect` | materialising a sequence the surrounding call would have iterated |
| `length_index_range` | looping over positions where the container can be iterated |
| `redundant_default` | passing the default as an explicit default |
| `empty_error_type` | an error type with no fields and no behaviour adds a name and nothing else |
| `type_equality` | exact-type comparison is false for every subtype |
| `nothing_equality` | `==` against the null literal compares where identity is meant |

## Scalar rules

These three count occurrences inside one definition rather than reporting each one. A
single null guard is a boundary; five mean the null travels and every caller downstream
inherits the guard.

| rule | what it counts | band |
| --- | --- | --- |
| `type_check_density` | runtime type checks that raise | `[3, 6]` |
| `null_guard_density` | null guards that return null | `[3, 15]` |
| `try_density` | independent try blocks | `[3, 15]` |

The warn edge of 3 is the count the [scb-check](https://github.com/gabeorlanski/scb-check)
rules hard-code as their verdict, kept as a fixed edge so a project has a standard rather
than only its own median. The high edges come from the measurement recorded above the
declarations in `builtin.toml`.

## Which rule fires in which language

A rule is declared once, language-independently, and realised per grammar. A language with
no query for a rule never fires it. That is ordinary: `except Exception: return None` has
no Go spelling, and an index loop is the idiom in JavaScript.

| rule | jl | py | js | ts | java | go | rs | c | cpp | php | rb | sh |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `banner_comment` | y | y | y | y | y | y | y | y | y | y | y | y |
| `boolean_return` | y | y | y | y | y | y | y | y | y | y | y | |
| `unreachable_branch` | y | y | y | y | y | y | y | y | y | y | y | y |
| `manual_min_max` | y | y | y | y | y | y | y | y | y | y | y | |
| `swallowed_error` | y | y | y | y | y | | | | y | y | y | |
| `boolean_equality` | y | y | y | y | y | y | y | y | y | y | y | |
| `empty_check` | y | y | y | y | y | | y | | y | y | y | |
| `redundant_conversion` | y | y | y | y | y | y | y | | y | y | y | |
| `redundant_keys` | y | y | y | y | y | | | | | y | y | |
| `redundant_collect` | y | y | | | | | | | | | | |
| `length_index_range` | y | y | | | | | y | | | | | |
| `redundant_default` | | y | | | | | | | | | | |
| `empty_error_type` | | y | y | y | y | | | | | y | y | |
| `type_equality` | y | y | | | y | | | | | | | |
| `nothing_equality` | y | y | | | | | | | | | | |
| `type_check_density` | y | y | y | y | y | | | | y | y | y | |
| `null_guard_density` | y | y | y | y | y | y | y | y | y | y | y | |
| `try_density` | y | y | y | y | y | | | | y | y | y | |

Several of the gaps are decisions somebody made.

- Julia has no `empty_error_type`. A fieldless `struct E <: Exception` is the dispatch
  mechanism, not a smell.
- JavaScript and TypeScript have no `nothing_equality`. `== null` is the deliberate loose
  check that catches `undefined` too.
- JavaScript and TypeScript have no `type_equality`, and no `length_index_range`: `typeof`
  is the idiom, and so is the index loop.
- Go, Rust and C have no `try_density` or `swallowed_error`, having no `try` to count.
- Go has no `empty_check`. `len(xs) == 0` is how Go asks whether a slice or map is empty,
  so the rule would name a fix the language does not offer.
- C has the fewest of any language with a query, six. The gaps are the language: no `try`,
  no container protocol behind a length, no key view, no exception type.
- Bash gets `banner_comment` and `unreachable_branch` and nothing else.

Dendro also carries `trivial_wrapper` as an optional built-in rule, off by default for
false positives. It strictly contains scb-check's identity-wrapper rule, `def f(x): return
g(x)`, so the pack adds no rule of its own for that shape. Turn it on with `[rules]
trivial_wrapper = true`.

## Changing one

The pack is layer zero of the same cascade a user-global config and a repo `.dendro.toml`
are layers of, so every lever a project has for its own rules works on a shipped one.

Turn a rule off by name:

```toml
[rules]
banner_comment = false
```

Retune a scalar's band:

```toml
[bands]
try_density = [2, 5]
```

Promote a flag so it fails the gate. A layer starts from the declaration below it, so
setting one key is all this takes; the message, kind and band come from the pack:

```toml
[patterns.boolean_return]
severity = "high"
```

Replace the declaration outright by writing the keys yourself. Last layer wins by key, so
a `message` here is what the finding says:

```toml
[patterns.empty_check]
message = "house rule: ask `isempty`, never `length(x) == 0`"
severity = "high"
```

Replace the *query* by writing your own `.dendro/patterns/<lang>.patterns.scm` with a
capture of that name. Shadowing is per rule per language, so a repo query for
`swallowed_error` in Julia leaves the shipped Python one alone, and leaves every other
Julia rule alone too.

Accept one finding without touching any of that by suppressing it inline, the way
[Suppressing findings](@ref) describes:

```julia
x == nothing  # dendro-ignore: nothing_equality -- comparing, not identifying, on purpose
```

## Where they came from

The flag rules follow
[SlopCodeBench](https://github.com/gabeorlanski/scb-check), which measures a "verbosity"
signal as the share of lines an ast-grep rule flags. That share is what separates
generated code from human code in the paper's sample, 0.32 against 0.11, where the clone
ratio barely moves. Dendro had the mechanism for such rules and shipped none of them, so
every project that wanted one wrote it.
