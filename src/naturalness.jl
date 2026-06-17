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
    token_stream(unit, profile, source) -> Vector{String}

The pre-order leaf tokens of a function unit, stopping at nested callables so each
is scored on its own. Each token abstracts identifier and literal text but keeps the
grammar's anonymous tokens, the shape an n-gram model reads.
"""
function token_stream(unit::FunctionUnit, profile::LanguageProfile, source::AbstractString)
    tokens = String[]
    collect_tokens!(tokens, unit.node, profile, source)
    return tokens
end

function collect_tokens!(tokens, node::TreeSitter.Node, profile::LanguageProfile, source::AbstractString)
    if TreeSitter.is_leaf(node)
        push!(tokens, token_of(node, source))
        return tokens
    end
    for c in TreeSitter.children(node)
        TreeSitter.node_type(c) in profile.function_types && continue
        collect_tokens!(tokens, c, profile, source)
    end
    return tokens
end

# Trigram counts over a corpus: each (w1, w2, w3) and its (w1, w2) context, plus the
# vocabulary size the smoothing spreads probability across.
struct NGramModel
    trigrams::Dict{Tuple{String,String,String},Int}
    contexts::Dict{Tuple{String,String},Int}
    vocabulary::Int
end

# One padded sequence's trigrams folded into the running counts and vocabulary.
function count_sequence!(trigrams, contexts, vocabulary, tokens)
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
function build_model(streams)
    trigrams = Dict{Tuple{String,String,String},Int}()
    contexts = Dict{Tuple{String,String},Int}()
    vocabulary = Set{String}()
    for tokens in streams
        count_sequence!(trigrams, contexts, vocabulary, tokens)
    end
    return NGramModel(trigrams, contexts, length(vocabulary))
end

"""
    cross_entropy(tokens, model) -> Float64

Mean bits per token to encode `tokens` under `model`: the smoothed surprise of each
token given its two predecessors, averaged. A higher value is a more surprising,
less idiomatic function.
"""
function cross_entropy(tokens, model::NGramModel)
    isempty(tokens) && return 0.0
    seq = [SEQ_START; SEQ_START; tokens]
    total = 0.0
    for i in NGRAM_ORDER:length(seq)
        context = (seq[i - 2], seq[i - 1])
        numerator = get(model.trigrams, (context[1], context[2], seq[i]), 0) + LAPLACE_ALPHA
        denominator = get(model.contexts, context, 0) + LAPLACE_ALPHA * model.vocabulary
        total -= log2(numerator / denominator)
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
function naturalness_units(files)
    bylang = Dict{Symbol,Vector{NaturalnessUnit}}()
    for f in files
        for unit in functions(f.tree, f.profile)
            tokens = token_stream(unit, f.profile, f.source)
            loc = Location(f.file, unit.firstline, unit_name(unit, f.profile, f.source))
            sup = is_suppressed(f.directives, unit.firstline, :unnatural)
            push!(get!(() -> NaturalnessUnit[], bylang, f.language), NaturalnessUnit(tokens, loc, sup))
        end
    end
    return bylang
end

# Naturalness findings for one language's units, scored against a model built from
# them. Skipped when the corpus is too thin to rank against.
function unnatural_in_language!(findings, units::Vector{NaturalnessUnit}, band, cut, min_tokens)
    sum(length(u.tokens) for u in units; init = 0) < min_tokens && return findings
    model = build_model([u.tokens for u in units])
    entropies = [cross_entropy(u.tokens, model) for u in units]
    sorted = sort(entropies)
    for (u, h) in zip(units, entropies)
        isempty(u.tokens) && continue
        value = round(Int, 100 * h)
        absolute = severity(value, band)
        pct = searchsortedlast(sorted, h) / length(sorted)
        (absolute != :ok || pct >= cut) || continue
        push!(findings, Finding(:unnatural, [u.location], value, absolute, pct, :scalar, u.suppressed))
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
function cluster_unnatural(files; band = UNNATURAL_BAND, cut::Real = 0.95,
                           min_tokens::Integer = MIN_CORPUS_TOKENS)
    findings = Finding[]
    for units in values(naturalness_units(files))
        unnatural_in_language!(findings, units, band, cut, min_tokens)
    end
    sort!(findings; by = f -> (-f.value, first(f.locations).file, first(f.locations).line))
    return findings
end
