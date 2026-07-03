# Reimplementation candidates. A helper rewritten with different structure shares no
# subtree shape with the original, so the clone passes miss it, but it usually keeps the
# original's vocabulary: the same callees, the same domain words in its identifiers.
# This pass fingerprints each function's names, weights each term by its rarity in the
# scanned corpus, and pairs functions whose shared rare vocabulary dominates their
# combined vocabulary. Names and counts only, no types, no dispatch, no pretrained
# model, and the rarity table is rebuilt from the corpus on every scan. The evidence is
# vocabulary, not structure, so the finding is proposal-strength: the pass is off by
# default, enabled with `[rules] reimplementation = true`.

# Score a candidate pair must reach, the IDF-weighted Jaccard of the two term sets.
const DEFAULT_REIMPL_THRESHOLD = 0.6

# Rare terms two units must share before they become a candidate pair. One shared rare
# term is a coincidence; two start to look like the same vocabulary.
const MIN_SHARED_RARE = 2

# A pair whose sizes differ beyond this ratio is a fragment against a whole, not a
# reimplementation, mirroring the length prefilter in `pair_similarity`.
const REIMPL_SIZE_RATIO = 0.5

# A term is rare, and so carries pairing evidence, up to this document frequency: 2% of
# the language's units, floored at 2 so a thin corpus still pairs. Below 2 a term
# appears in one unit and can pair nothing.
rare_df_cap(n::Int) = max(2, cld(n, 50))

"""
    subtokens(name) -> Vector{String}

The lowercase word fragments of one identifier, split on non-alphanumeric characters
and camel-case boundaries, acronyms kept whole (`parseHTTPResponse` splits to
`parse`, `http`, `response`). Single characters and all-digit fragments drop out,
too generic to carry vocabulary.
"""
function subtokens(name::AbstractString)
    out = String[]
    for run in eachsplit(name, r"[^A-Za-z0-9]+"; keepempty = false)
        marked = replace(
            run,
            r"(?<=[a-z0-9])(?=[A-Z])" => '\0',
            r"(?<=[A-Z])(?=[A-Z][a-z])" => '\0'
        )
        for frag in eachsplit(marked, '\0'; keepempty = false)
            length(frag) <= 1 && continue
            all(isdigit, frag) && continue
            push!(out, lowercase(frag))
        end
    end
    return out
end

# One function carried through reimplementation detection: where it is, whether an
# author accepted it, its name, its distinct callee names, its fingerprint terms
# (namespaced callees plus identifier subtokens), its exact digest (to skip exact
# clones), and its size.
struct ReimplUnit
    language::Symbol
    location::Location
    suppressed::Bool
    name::String
    callees::Set{String}
    terms::Set{String}
    digest::UInt64
    size::Int
end

# Every function unit of the corpus at or above the size floor, fingerprinted. One
# pass over a file's `@name` captures attributes identifier subtokens to the innermost
# unit, so a nested callable's vocabulary belongs to it, not its host; callee names
# arrive namespaced (`c:` prefix) so a whole-callee match and a coincidental subtoken
# never share one rarity count.
function reimpl_units(files::Vector{ParsedFile}, min_size::Int)
    out = ReimplUnit[]
    for f in files
        units = functions(f.index)
        isempty(units) && continue
        ranges = unit_ranges(f.index)
        callees = callees_by_unit(f.index)
        idents = [Set{String}() for _ in units]
        for n in f.index.name.nodes
            nid = nodeid(n)
            ui = containing_unit(ranges, nid[1], nid[2])
            ui == 0 && continue
            union!(idents[ui], subtokens(TreeSitter.slice(f.index.source, n)))
        end
        for (i, unit) in enumerate(units)
            root = subtrees(unit, f.index)[end]
            root.size < min_size && continue
            terms = Set{String}("c:" * c for c in callees[i])
            union!(terms, idents[i])
            loc = Location(f.file, unit.firstline, unit_name(unit, f.index))
            sup = is_suppressed(f.directives, unit.firstline, RELATIONAL.reimplementation)
            push!(out, ReimplUnit(f.language, loc, sup, loc.unit, callees[i], terms, root.hash, root.size))
        end
    end
    return out
end

# The IDF table and rare-term set for one language's units. IDF is smoothed,
# `log2((N + 1) / (df + 1))`, so a term in every unit weighs near zero and a hapax
# weighs most; the rare set spans `2 <= df <= rare_df_cap(N)`, the terms concentrated
# enough to carry pairing evidence.
function term_stats(units::Vector{ReimplUnit}, idxs::Vector{Int})
    df = Dict{String, Int}()
    for i in idxs, t in units[i].terms
        df[t] = get(df, t, 0) + 1
    end
    n = length(idxs)
    idf = Dict{String, Float64}(t => log2((n + 1) / (d + 1)) for (t, d) in df)
    cap = rare_df_cap(n)
    rare = Set{String}(t for (t, d) in df if 2 <= d <= cap)
    return idf, rare
end

# Candidate pairs within one language, from an inverted index on rare terms: the score
# is zero unless the pair shares vocabulary, so posting lists enumerate exactly the
# pairs that can pass, and the rare-df cap bounds each list. Deterministic: units are
# scanned in collection order and the surviving pairs sorted.
function reimpl_candidates(units::Vector{ReimplUnit}, idxs::Vector{Int}, rare::Set{String})
    posting = Dict{String, Vector{Int}}()
    for i in idxs, t in units[i].terms
        t in rare && push!(get!(() -> Int[], posting, t), i)
    end
    shared = Dict{Tuple{Int, Int}, Int}()
    for list in values(posting)
        for a in 1:(length(list) - 1), b in (a + 1):length(list)
            pair = minmax(list[a], list[b])
            shared[pair] = get(shared, pair, 0) + 1
        end
    end
    return sort!([p for (p, c) in shared if c >= MIN_SHARED_RARE])
end

# The IDF-weighted Jaccard of two fingerprints: shared IDF mass over combined IDF
# mass. Symmetric, in [0, 1], and explainable, the fraction of the pair's distinctive
# vocabulary they share.
function reimpl_score(a::ReimplUnit, b::ReimplUnit, idf::Dict{String, Float64})
    inter = 0.0
    combined = 0.0
    for t in a.terms
        w = idf[t]
        combined += w
        t in b.terms && (inter += w)
    end
    for t in b.terms
        t in a.terms && continue
        combined += idf[t]
    end
    combined == 0.0 && return 0.0
    return inter / combined
end

# A location's identity for pair bookkeeping.
lockey(l::Location) = (l.file, l.line, l.unit)

# Unordered location pairs the clone passes already reported, keyed by `lockey` in
# both orders so membership is one lookup. A pair the structural passes claimed is
# their finding, not a reimplementation candidate.
function clone_pairs(findings::Vector{Finding})
    pairs = Set{NTuple{2, Tuple{String, Int, String}}}()
    for f in findings
        locs = f.locations
        for x in 1:(length(locs) - 1), y in (x + 1):length(locs)
            a, b = lockey(locs[x]), lockey(locs[y])
            push!(pairs, (a, b), (b, a))
        end
    end
    return pairs
end

"""
    cluster_reimplementations(files; min_size, threshold, clone_findings) -> Vector{Finding}

Reimplementation candidates across the corpus, keyed by language: one `:reimplementation`
finding per pair of functions whose IDF-weighted vocabulary overlap reaches `threshold`,
its `value` the overlap as a percent. A pair is skipped when the two sizes differ beyond
`REIMPL_SIZE_RATIO`, when the digests match (an exact clone), when the names match
(overloads and interface methods share vocabulary legitimately), when either unit calls
the other by name (a caller shares its callee's vocabulary, and a reimplementation does
not call the original), or when `clone_findings` already reports the pair. Suppressed
when either member carries a `dendro-ignore: reimplementation` directive.
"""
function cluster_reimplementations(
        files::Vector{ParsedFile}; min_size::Integer = DEFAULT_MIN_SIZE,
        threshold::Real = DEFAULT_REIMPL_THRESHOLD,
        clone_findings::Vector{Finding} = Finding[]
    )
    units = reimpl_units(files, Int(min_size))
    cloned = clone_pairs(clone_findings)
    bylang = Dict{Symbol, Vector{Int}}()
    for (i, u) in enumerate(units)
        push!(get!(() -> Int[], bylang, u.language), i)
    end
    thr = Float64(threshold)
    findings = Finding[]
    for lang in sort!(collect(keys(bylang)))
        idxs = bylang[lang]
        length(idxs) < 2 && continue
        idf, rare = term_stats(units, idxs)
        for (i, j) in reimpl_candidates(units, idxs, rare)
            a, b = units[i], units[j]
            min(a.size, b.size) < REIMPL_SIZE_RATIO * max(a.size, b.size) && continue
            a.digest == b.digest && continue
            a.name == b.name && continue
            (b.name in a.callees || a.name in b.callees) && continue
            (lockey(a.location), lockey(b.location)) in cloned && continue
            score = reimpl_score(a, b, idf)
            score >= thr || continue
            locations = sort([a.location, b.location]; by = l -> (l.file, l.line))
            push!(
                findings, Finding(
                    RELATIONAL.reimplementation, locations, round(Int, 100 * score),
                    :high, nothing, :flag, a.suppressed || b.suppressed
                )
            )
        end
    end
    sort!(
        findings; by = f -> (
            -(f.value::Int), first(f.locations).file, first(f.locations).line,
            last(f.locations).file, last(f.locations).line,
        )
    )
    return findings
end
