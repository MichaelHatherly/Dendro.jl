# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- User-authored lint rules, a second tree-sitter query family. A `[patterns.<name>]` table
  in `.dendro.toml` declares a rule, language-independently, and a
  `.dendro/patterns/<lang>.patterns.scm` capture realises it for one grammar. A flag rule
  reports each match; a scalar rule counts its matches per unit and is scored against a
  band and the corpus percentile like any built-in. A rule resolves to an ordinary `Rule`,
  so suppression, diff scoping, the report, the gate, and the ratchet all work for it with
  no further code. Rules compose across a repo directory and a user-global one, the repo's
  winning where both define the same rule for a language.
- Negation in a rule query. A `@rule.not` capture subtracts from `@rule` by node identity,
  which is how a rule says "without": a `catch` binding no exception, a `switch` with no
  default, a function with no return type. Tree-sitter anchors were the alternative and
  break on a comment between the keyword and the block.
- Query fragments. A `; fragment: <name> = ...` comment defines a named piece of query text
  and a reference splices it, so several rules about one construct stop repeating its
  shape. Expansion is line-preserving and carries a source map, so an error inside a
  fragment names the fragment, where it was defined, and where it was used.
- `check_patterns` and a `--check-patterns` flag, testing a rule against fixtures. A
  fixture marks the lines a rule must match; a marked line it missed and an unmarked line
  it matched both fail, so a rule matching everything cannot pass.
- Every way of getting a rule wrong is now loud: a bad node type, field, capture reference,
  or syntax error fails when the query compiles and names the file and line; a predicate
  TreeSitter.jl does not implement is rejected at load rather than silently rejecting every
  match; a capture naming no declared rule is a load error, catching a typo and a predicate
  helper that lost its `_` prefix; and a rule that compiled cleanly but matched nothing
  anywhere in the corpus is reported after the scan.
- Opt-in corpus finding `:divisible_package`: a directory whose direct children divide into
  groups that could become subdirectories. Where `:incoherent_package` asks whether a
  directory's contents belong elsewhere, this asks whether contents that do belong are
  missing an internal shape. It reads the file graph induced on one directory's children, a
  child file as one node and a child directory as one node with everything under it
  contracted in, so one rule covers a directory of files splitting into folders and a
  directory of folders grouping under new parents. The score is the best proposed folder's
  internal reference ratio, and the finding names the children each folder takes.
  `[rules] divisible_package = true` enables it; banded `[60, 85]`.
- Opt-in corpus finding `:distant_definition`: a definition separated from the code that
  uses it, the within-file companion to `:misplaced`. The score is how many top-level
  definitions lie between a definition and the nearest unit in its file that references it,
  so a definition written beside a use scores zero. Nearest rather than mean or median, and
  that is what keeps the rule quiet on a file-wide helper without a ubiquity cut: such a
  name has a use close by wherever it sits. The finding names the definition and the use
  nearest it. Measured over 5798 scored definitions in nine corpora, separation is ordinary
  and the tail is long, so the band marks only what is beyond argument and the rule ships
  off. `[rules] distant_definition = true` enables it; banded `[25, 50]`.

### Changed

- A scalar's corpus percentile is read only where the distribution supports a rank. A
  metric that is zero across most of a corpus has a rank that stops ranking: once the share
  of units holding nothing passes the cut, every unit sits above it and the rule reports
  each function for containing nothing. Measured on one corpus, `boolean_complexity`
  reported 2756 findings across 2756 units. Across eight corpora `cyclomatic` and
  `function_length` do not move at all and `cognitive_complexity` moves by four findings in
  450, while `boolean_complexity` falls 97.8%. The absolute bands are untouched.
- `:scattered`'s band moves from `(4, 6)` to `(7, 10)`, the first measurement of it. Over
  261 scored files across ten corpora the pooled median is 2 and the p90 is 6, so `high` at
  6 put 11.5% of scored files, in five of the ten corpora, into the error floor every
  dogfooding package gates on. At 10 it fires on 4 of Makie's 145 files and on nothing else
  measured, and `warn` at 7 sits above the p90 of every corpus but one. A file below the
  band still reports where it ranks in the top 5% of its own corpus, so a corpus whose
  worst file scores 6 is not silent.

### Fixed

- A `[languages.<name>] queries` path now resolves against the config file that declared
  it rather than the process working directory, so a scan started from a subdirectory finds
  the queries. `patterns_dir` behaves the same way.
- A `[bands]` override for a rule declared in the same file is no longer dropped depending
  on TOML dictionary iteration order. Top-level config keys apply in a fixed order.
- The unit-level change diagram draws references, so an arrow says which unit reached for
  which. It drew the edges cohesion partitions on, which relate every unit sharing a
  definition and carry no direction of their own, so the picture took one from whichever
  unit the file's bindings happened to resolve to first. A commit here that changed a single
  function reported 24 moved edges among functions that were byte-identical across it, some
  of them the same pair with the arrow reversed; it now reports the two the edit moved. A
  definition at file scope is a node of its own, so the functions reading a constant point
  at it rather than at each other.
- `:scattered` no longer moves on the order a file's bindings resolve in. The within-file
  edges a file contributed joined one arbitrarily chosen unit to the rest and weighted each
  by that unit's reference count, so the same code yielded different weights, a different
  community partition and a different score depending on which unit came first. Every pair
  of units sharing a file-local definition is now joined, weighted by how many definitions
  the pair shares, which also stops calling one helper three times reading as three times
  the coupling. `:low_cohesion` is unchanged, since the added edges sit inside a component
  the old shape already connected.
- A source file holding an embedded NUL byte is reported and skipped instead of taking the
  whole scan down. Tree-sitter takes the source as a C string, so a byte no C string can
  carry is a file the parser will never accept. A corpus holds one now and then, a fuzzer
  test case checked in beside real source. The path is named in a warning, since naming it
  is what tells a skipped file from a clean one.
- A reference qualified by a namespace (`Mod.f`) now resolves to the definition inside
  that namespace. A definition inside a Julia `module` that an included file declares
  never joins the includer's namespace, so nothing reached it by bare name and the splice
  model saw it as visible to no file: `:unreferenced` reported every definition in a
  package built out of submodules, and `:misplaced` and `:scattered` read none of that
  coupling. Matching is on the namespace enclosing a definition directly, so a longer
  qualifier (`Tools.Knowledge.search`) resolves too. A definition at file scope answers to
  the qualified form as well as the bare one. Its file was spliced into whatever module
  the `include` sits inside, a namespace the file itself never declares, so the corpus now
  walks the splice chain to find it. A field read
  (`row.total`) no longer resolves as a bare `total`, since a value's field matches no
  namespace. Julia only for now; the other splice languages keep their bare-name
  resolution until their namespace access is tested.

### Added

- The corpus file dependency graph, the substrate for the rules that read the corpus as
  files depending on files. Nodes are corpus files; an edge counts the references crossing
  from one to another and carries the definition names behind it and the import statement
  that admits it, so a finding built on it names an edit rather than a score. It reads the
  same name-based, lexical resolution the unit graph does, and keeps the cross-cutting
  references that graph drops: a file everything reaches for is what an architecture
  question is about, where placement needs it discounted. `module_graph` contracts it by
  directory, which every language has, where a declared module is available in some and not
  others.
- Corpus finding `:back_edge`: a reference running against the direction two directories
  have settled on. Contract the file graph by directory and read the reference weight each
  way; a pair whose majority direction carries enough traffic scores the dominance percent,
  `100 * major / (major + minor)`. The layering is inferred from the corpus, so no declared
  layer map is involved. One finding per file edge in the minority direction, located at the
  import statement and then every reference across it, so a diff that adds a use of an
  already-imported name still scopes in under `base`. A pair spreading its minority side
  over more than five file edges reports below `:high` whatever its dominance: no single
  edit exists to propose, and one observation should not become a dozen gate errors. Banded
  `[85, 95]`, tunable as `back_edge`, suppressible with `dendro-ignore: back_edge`.
- Corpus finding `:dependency_cycle`: files depending on one another in a loop, reported as
  the edges whose removal breaks it. Membership alone names no edit, since Melton and
  Tempero measured cycles spanning a hundred classes in around 45% of the Java applications
  they studied. Tarjan finds each strongly connected component, and the Eades-Lin-Smyth
  heuristic weighted by reference count proposes the cuts, so it prefers cutting three edges
  carrying one reference each over one carrying two hundred. Each location reads
  `cut -> <target>` at the import admitting that edge. A component whose feedback set
  exceeds six cuts has no bounded edit, so the finding switches to naming the tangle's
  busiest members and carries the true cut count. Scored on the component size, banded
  `[5, 10]`, tunable as `dependency_cycle`.
- Corpus finding `:hub`: a file that both depends on much of the corpus and is depended on
  by much of it, the position carrying the highest measured defect density. The score is
  `min(fan_in, fan_out)` over distinct files, since fan-in alone is every utility and
  fan-out alone every orchestrator. The proposal is the split: where the hub's
  externally referenced definitions fall into two or more audiences, one representative per
  audience follows the file, each labelled with the files consuming it. A hub whose
  consumers all reach the whole file carries the file alone rather than dressing one group
  up as a proposal. Both counts grow with the corpus, so the percentile does most of the
  work here. Banded `[15, 30]`, tunable as `hub`.
- Corpus finding `:split_audience`: a file whose definitions serve two or more groups of
  consumers that never meet, the outward dual of `:low_cohesion`. Two definitions belong to
  one audience when a consumer reaches both, and the score is the count of audiences holding
  at least two definitions. References resolve the audience; declared exports do not, so it
  reads the same in a language with no export marker, where an export-counting reading would
  collapse into file size. Locations are one representative
  definition per audience, labelled with the files consuming it. Banded `[3, 5]`, tunable as
  `split_audience`.
- Opt-in corpus finding `:incoherent_package`: a directory whose units mostly sit in
  communities anchored in other directories. The score is a percentage, so a large directory
  compares with a small one; a count would only say the directory was large. What it
  proposes is a rearrangement, not a bounded edit, and it restates per directory much of
  what `:scattered` reports per file, so it ships off by default and never enters the
  `errors` floor. `[rules] incoherent_package = true`
  enables it; banded `[50, 75]`.
- Clone clusters rank by how far apart their members sit in the module graph: within one
  file, within one directory, within one community of directories, or across communities.
  Two copies either side of a boundary are a missing abstraction where two copies in one
  file are a tidy-up. Ranking only, so no finding's value, band, or membership of the
  `errors` floor moves.
- `Location` carries a label, what a site means to the finding holding it. `:scattered`
  names the file each unit belongs with, `:split_audience` and `:hub` the files consuming
  each audience. Recovering that otherwise means rebuilding the corpus graph by hand, work
  the pass has already done. The gate keys on file and unit alone, so labelling a site never
  moves a ratchet key.
- `:unreferenced` roots a definition a macro consumes directly (`@GET function
  handler(req) ... end`, and other route, test, or component macros): no in-corpus call
  reaches it, yet it is a live entry point, so it seeds the reachability search instead
  of reading as dead. A transparent wrapper (`@inline`, `@kwdef`, and the like) does not
  root, and a helper nested in a wrapped `begin` block is unaffected. Generic across
  languages through a per-language `Linkage.external_root`; Julia is populated, other
  languages opt in.
- Opt-in corpus finding `:reimplementation`: two functions whose IDF-weighted
  vocabulary overlap (callee names plus identifier word fragments, rarity from the
  scanned corpus) clears a threshold, the rewrite-with-different-structure the
  structural clone passes miss. Pairs already reported as clones, caller/callee
  pairs, same-named functions, and 2:1 size mismatches are skipped. Off by
  default; `[rules] reimplementation = true` enables it and `[reimplementation]
  threshold` tunes the cutoff (default 0.6). Suppressible with
  `dendro-ignore: reimplementation`.
- Flag metrics `unused_parameter` and `unused_local`: a parameter or local binding
  whose name nothing in its function references. The use-test is by name over the
  whole unit, so a reference in a nested closure counts; a leading underscore opts
  a name out. Bodyless declarations, empty and stub bodies, and top-level bindings
  are not reported (the latter belong to `unreferenced`). Both are built-in rules,
  suppressible inline and toggleable from `[rules]` in `.dendro.toml`.
- The Julia scopes query captures a local binding only from a statement-position
  assignment, so a call-site keyword argument (`sort!(xs; by = f)`) and a
  NamedTuple field (`(added = true,)`) no longer read as bindings. The bash scopes
  query captures `variable_name` references, so `$x` resolves to its assignment.
- Optional rules `local_count` (distinct local names bound in a function, band
  10/15) and `shadowed_variable` (a fresh local binding hiding an enclosing one).
  The Julia scopes query splits binding kinds to support the latter: a `for`/`let`
  head is a fresh binding, a statement assignment rebinds an enclosing local, so
  the accumulator idiom never reads as a shadow.
- Flag metric `broad_catch`: a handler broad enough to swallow interrupts and
  exits. A bare `except:`, `except BaseException`, Java `catch (Throwable)`, C++
  `catch (...)`, Ruby `rescue Exception`, PHP `catch (Throwable)`. The merely-wide
  tier (`except Exception`, `catch (Exception)`) is not flagged, and a language
  whose only catch form is untyped (JavaScript, Julia) reports nothing.
- Optional rule `fan_out`: distinct callables a function invokes, by called name,
  a member call counted by its final name, recursion excluded. Band 12/20,
  anchored at the p95/p99 of a six-corpus calibration; opt-in because no fixed
  band separates a smell from a legitimate orchestrator.
- `analyze(path; base, cut, min_size, language)` takes a file or folder. A folder
  recurses for analysable files; either way a baseline is built from the corpus
  (the folder's files, or the single file's own functions), so relative scoring
  works against the input's own distribution with no setup. `base` scopes to a git
  diff, reporting only functions changed against that ref. Every analysis reports
  per-function metrics and cross-file duplicates, tolerant to identifier renaming
  and literal-value changes (Type-2 clones), each cluster of two or more functions
  one `:duplicate` finding whose `locations` list every member. `min_size`
  (named-node count) gates trivial duplicates, suppressed by
  `dendro-ignore: duplicate` on any member.
- Scalar metrics per function: cyclomatic complexity, length, maximum nesting
  depth, parameter count, each with a documented absolute severity band.
- Flag metrics: swallowed errors (empty catch clauses), stub markers
  (`TODO`/`FIXME`/`XXX`/`HACK`), and empty function bodies.
- Dual scoring. Every `Finding` carries the absolute band and the corpus
  percentile, so outliers surface against both a fixed standard and the codebase's
  own distribution.
- Inline suppression directives in comments: `dendro-ignore` for the same or next
  line, `dendro-ignore: cyclomatic, parameter_count` for named metrics, and
  `dendro-ignore-file` for a whole file. Works in every supported language. An
  unknown metric name warns. A suppressed finding is marked, not dropped, so the
  rendered report shows a count of suppressions and `active(findings)` returns the
  unsuppressed findings for gating.
- A `Finding` spans a set of `Location`s rather than a single file/line/unit, so a
  relational metric like `:duplicate` reports every site it covers. Per-file
  metrics fire at one location.
- `analyze` returns `Findings`, an `AbstractVector{Finding}` that prints as a
  report; render it elsewhere with `show(io, MIME("text/plain"), findings)`.
- Lazy parser resolution: a language name loads its `tree_sitter_<lang>_jll` on
  demand, so Dendro depends on no grammars itself.
- Language profiles for bash, c, cpp, go, java, javascript, julia, php, python,
  ruby, rust, typescript.
- Dendro exports nothing. The API (`analyze`, `active`, `github_annotations`,
  `Finding`, `Findings`, `Location`, `Rule`, `BUILTIN_RULES`, `OPTIONAL_RULES`) is
  marked `public`, so `using Dendro` brings no names into scope; import what you
  call or qualify with `Dendro.`. The `public` keyword sets the minimum Julia to
  1.11.
