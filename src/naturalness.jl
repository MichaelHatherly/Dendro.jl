# Naturalness scoring. A function whose token sequence is structurally surprising
# under the rest of the corpus reads as unidiomatic, and surprise correlates with
# bugs and smells. An n-gram model over the corpus gives each function a cross-entropy
# in bits per token; the model compares structure, never resolves a symbol, so it
# stays inside the syntactic bargain. This crosses the single-file boundary the same
# way duplicate detection does, and within one language.

# Trigram model with add-one smoothing. Three is enough context to catch local idiom
# without splitting the counts so fine that every function looks novel.
const NGRAM_ORDER = 3
const LAPLACE_ALPHA = 1.0

# A language's model needs this many tokens before its scores mean anything; under it
# the counts are too sparse and every function scores as surprising. A single small
# file falls below it and reports nothing, as percentile scoring does on a thin corpus.
const MIN_CORPUS_TOKENS = 1000

# Interpolation weight on the global model against the per-file cache, `P = λ·P_global
# + (1-λ)·P_cache`. Code is locally repetitive (Tu et al., "On the Localness of
# Software"), so a function read against its own file's idiom stands out only when it
# breaks that idiom, not merely the corpus's. A fixed 0.5 is the Jelinek-Mercer weight
# Hellendoorn & Devanbu found best for code, and the fewest parameters.
const CACHE_LAMBDA = 0.5

# Absolute band on cross-entropy, in centibits (bits * 100), so it fits the integer
# `severity` band like every other scalar. Cross-entropy has no external standard the
# way cyclomatic does, so this floor is empirical: set well above an idiomatic
# corpus's spread, the level at which a function is structurally unusual enough to
# read regardless of how the rest of the corpus scores. The percentile is the signal
# that tracks the corpus; this only keeps a coherent codebase, our own included, from
# flagging on the absolute score. The ceiling is near log2(vocabulary): a function
# whose trigrams are all novel scores about that, so this floor sits just below it,
# reached only by near-random structure.
const UNNATURAL_BAND = (400, 500)

# Sentinel marking the start of a token sequence, padded so the first real token is
# predicted from context like any other. Bracketed so it never collides with a real
# leaf's node type or text.
const SEQ_START = "<seq-start>"

# The model's token for one leaf: a named leaf (identifier, literal) reduces to its
# node type, dropping the name or value, while an anonymous leaf (operator, keyword,
# punctuation) keeps its text, so distinct idioms stay distinct where the grammar
# spells them as separate tokens.
token_of(node::TreeSitter.Node, source::AbstractString) =
    TreeSitter.is_named(node) ? TreeSitter.node_type(node) :
    String(strip(TreeSitter.slice(source, node)))

"""
    token_stream(unit, index) -> Vector{String}

The pre-order leaf tokens of a function unit, stopping at nested callables so each
is scored on its own. Each token abstracts identifier and literal text but keeps the
grammar's anonymous tokens, the shape an n-gram model reads.
"""
# Shares the `collect_unit` entry shape with `subtrees`; the collectors and element
# types differ, so the one-line wrappers collide with nothing to extract.
# dendro-ignore: duplicate
token_stream(unit::FunctionUnit, index::QueryIndex) =
    collect_unit(collect_tokens!, String, unit, index)

function collect_tokens!(tokens::Vector{String}, node::TreeSitter.Node, index::QueryIndex)
    if TreeSitter.is_leaf(node)
        push!(tokens, token_of(node, index.source))
        return tokens
    end
    for c in TreeSitter.children(node)
        is_function(c, index) && continue
        collect_tokens!(tokens, c, index)
    end
    return tokens
end

# Trigram counts over a corpus: each (w1, w2, w3) and its (w1, w2) context, plus the
# vocabulary size the smoothing spreads probability across.
struct NGramModel
    trigrams::Dict{Tuple{String, String, String}, Int}
    contexts::Dict{Tuple{String, String}, Int}
    vocabulary::Int
end

# One padded sequence's trigrams folded into the running counts and vocabulary.
function count_sequence!(
        trigrams::Dict{Tuple{String, String, String}, Int},
        contexts::Dict{Tuple{String, String}, Int},
        vocabulary::Set{String}, tokens::Vector{String}
    )
    seq = [SEQ_START; SEQ_START; tokens]
    for t in tokens
        push!(vocabulary, t)
    end
    for i in NGRAM_ORDER:length(seq)
        key = (seq[i - 2], seq[i - 1], seq[i])
        context = (seq[i - 2], seq[i - 1])
        trigrams[key] = get(trigrams, key, 0) + 1
        contexts[context] = get(contexts, context, 0) + 1
    end
    return nothing
end

"""
    build_model(streams) -> NGramModel

A trigram model over every token stream in one language's corpus.
"""
function build_model(streams::AbstractVector{Vector{String}})
    trigrams = Dict{Tuple{String, String, String}, Int}()
    contexts = Dict{Tuple{String, String}, Int}()
    vocabulary = Set{String}()
    for tokens in streams
        count_sequence!(trigrams, contexts, vocabulary, tokens)
    end
    return NGramModel(trigrams, contexts, length(vocabulary))
end

# Smoothed conditional probability of `t` following context `(c1, c2)` under `model`,
# add-one over the model's vocabulary.
smoothed_prob(model::NGramModel, c1::String, c2::String, t::String) =
    (get(model.trigrams, (c1, c2, t), 0) + LAPLACE_ALPHA) /
    (get(model.contexts, (c1, c2), 0) + LAPLACE_ALPHA * model.vocabulary)

"""
    interpolated_cross_entropy(tokens, global_model, cache, λ) -> Float64

Mean bits per token to encode `tokens` under the linear interpolation `λ·P_global +
(1-λ)·P_cache` of the corpus model and a local cache model (Tu et al.): the smoothed
surprise of each token given its two predecessors, averaged. A higher value is a more
surprising, less idiomatic function.
"""
function interpolated_cross_entropy(tokens::Vector{String}, global_model::NGramModel, cache::NGramModel, λ::Float64)
    isempty(tokens) && return 0.0
    seq = [SEQ_START; SEQ_START; tokens]
    total = 0.0
    for i in NGRAM_ORDER:length(seq)
        c1, c2, t = seq[i - 2], seq[i - 1], seq[i]
        p = λ * smoothed_prob(global_model, c1, c2, t) + (1 - λ) * smoothed_prob(cache, c1, c2, t)
        total -= log2(p)
    end
    return total / length(tokens)
end

# One function carried through naturalness scoring: its token stream, where it is, and
# whether an author accepted the finding.
struct NaturalnessUnit
    tokens::Vector{String}
    location::Location
    suppressed::Bool
end

# Collect every function in the corpus as a NaturalnessUnit, grouped by language so a
# model never mixes grammars.
function naturalness_units(files::Vector{ParsedFile})
    bylang = Dict{Symbol, Vector{NaturalnessUnit}}()
    for f in files
        for unit in functions(f.index)
            tokens = token_stream(unit, f.index)
            loc = Location(f.file, unit.firstline, unit_name(unit, f.index))
            sup = is_suppressed(f.directives, unit.firstline, RELATIONAL.unnatural)
            push!(get!(() -> NaturalnessUnit[], bylang, f.language), NaturalnessUnit(tokens, loc, sup))
        end
    end
    return bylang
end

# Per-file cache models: a trigram model over the token streams in each file, the
# local idiom each of its functions is read against. No capturing closure, so the
# accumulators stay concretely typed.
function file_caches(units::Vector{NaturalnessUnit})
    byfile = Dict{String, Vector{Vector{String}}}()
    for u in units
        streams = get(byfile, u.location.file, nothing)
        if streams === nothing
            streams = Vector{String}[]
            byfile[u.location.file] = streams
        end
        push!(streams, u.tokens)
    end
    caches = Dict{String, NGramModel}()
    for (file, streams) in byfile
        caches[file] = build_model(streams)
    end
    return caches
end

# Naturalness findings for one language's units, scored against a global model
# interpolated with each unit's file cache. Skipped when the corpus is too thin to
# rank against.
function unnatural_in_language!(
        findings::Vector{Finding}, units::Vector{NaturalnessUnit},
        band::Tuple{Int, Int}, cut::Real, min_tokens::Integer
    )
    sum(length(u.tokens) for u in units; init = 0) < min_tokens && return findings
    global_model = build_model([u.tokens for u in units])
    caches = file_caches(units)
    # A plain loop, not a comprehension, so the captured models stay concretely typed.
    entropies = Vector{Float64}(undef, length(units))
    for (i, u) in enumerate(units)
        entropies[i] = interpolated_cross_entropy(u.tokens, global_model, caches[u.location.file], CACHE_LAMBDA)
    end
    sorted = sort(entropies)
    for (u, h) in zip(units, entropies)
        isempty(u.tokens) && continue
        value = round(Int, 100 * h)
        absolute = severity(value, band)
        pct = searchsortedlast(sorted, h) / length(sorted)
        (absolute != :ok || pct >= cut) || continue
        push!(findings, Finding(RELATIONAL.unnatural, [u.location], value, absolute, pct, :scalar, u.suppressed))
    end
    return findings
end

"""
    cluster_unnatural(files; band=$UNNATURAL_BAND, cut=0.95, min_tokens=$MIN_CORPUS_TOKENS) -> Vector{Finding}

Functions whose token sequence is surprising under their language's corpus model,
reported as `:unnatural`. Each carries both scores: the absolute cross-entropy `band`
in centibits, and the corpus percentile, fired when either trips. A language with
fewer than `min_tokens` tokens is skipped, its model too sparse to rank against.
"""
function cluster_unnatural(
        files::Vector{ParsedFile}; band::Tuple{Int, Int} = UNNATURAL_BAND, cut::Real = 0.95,
        min_tokens::Integer = MIN_CORPUS_TOKENS
    )
    findings = Finding[]
    for units in values(naturalness_units(files))
        unnatural_in_language!(findings, units, band, cut, min_tokens)
    end
    sort!(findings; by = f -> (-something(f.value), first(f.locations).file, first(f.locations).line))
    return findings
end
