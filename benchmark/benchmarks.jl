# Runtime benchmarks for Dendro.jl
#
# Run with: julia --project=benchmark benchmark/run.jl
# Or interactively: include("benchmark/benchmarks.jl"); run(SUITE)
#
# Inputs are chosen for stable trends. `analyze/corpus` runs the public pipeline
# over the multi-language test corpus, which drifts only when a fixture is added.
# `parse/<lang>` parses one fixed fixture file per language. `stages/*` run the
# clustering passes over a synthetic corpus of a pinned size, so a movement there
# is the algorithm changing, not the input. The codebase's own `src/` is not an
# input: its size changes every commit, which would confound a historical trend.

import BenchmarkTools
import Dendro

# Timings are only comparable single-threaded: `analyze` fans out across threads above a
# corpus-size floor, and the calibration normalizer assumes identical work every run. The
# `just bench*` recipes pass `-t1`; fail loud if something starts the suite with more.
Threads.nthreads() == 1 ||
    error("benchmarks must run single-threaded (nthreads=$(Threads.nthreads())); run with `-t1`")

const SUITE = BenchmarkTools.BenchmarkGroup()

const CORPUS_DIR = joinpath(@__DIR__, "..", "test", "corpus")

# === Runner-speed calibration ===
# A fixed, allocation-free compute kernel whose only job is to measure how fast the
# runner is on a given run. `compare.jl` divides it out so a wall-clock delta
# reflects the code, not a shared CI runner that happened to be slower that day.
# The iteration count is pinned forever: changing it rebases every future
# comparison against a different clock.
const CALIBRATION_ITERATIONS = 500_000

function calibration_kernel(n::Int)
    acc = 0.0
    x = 1.0
    for _ in 1:n
        x = muladd(x, 1.000_000_1, 1.0)
        acc += x - floor(x)
    end
    return acc
end

SUITE["calibration"] =
    BenchmarkTools.@benchmarkable calibration_kernel($CALIBRATION_ITERATIONS)

# === End-to-end ===
# The public pipeline over the whole test corpus: parse, baseline, per-file scoring,
# duplicate, naturalness, and cohesion passes across all languages.
SUITE["analyze"] = BenchmarkTools.BenchmarkGroup()
SUITE["analyze"]["corpus"] = BenchmarkTools.@benchmarkable Dendro.analyze($CORPUS_DIR)

# === Per-language parse + index ===
# One representative file per language (the largest fixture), isolating tree-sitter
# parsing, query matching, and binding resolution from the rest of the pipeline.
const PARSE_TARGETS = let targets = Tuple{Symbol, String}[]
    for lang in sort(readdir(CORPUS_DIR))
        dir = joinpath(CORPUS_DIR, lang)
        isdir(dir) || continue
        files = filter(f -> startswith(f, "complexity."), readdir(dir))
        isempty(files) && continue
        push!(targets, (Symbol(lang), joinpath(dir, first(files))))
    end
    targets
end

# Build the benchmarkable in a function so each `$`-interpolation captures its own
# `lang`/`files`, not the loop's last binding.
parse_bench(lang::Symbol, files::Vector{String}) =
    BenchmarkTools.@benchmarkable Dendro.parse_corpus($files; language = $lang)

SUITE["parse"] = BenchmarkTools.BenchmarkGroup()
for (lang, file) in PARSE_TARGETS
    SUITE["parse"][string(lang)] = parse_bench(lang, [file])
end

# === Synthetic corpus for the clustering passes ===
# A deterministic set of Julia functions at a pinned size. Functions sharing a body
# shape are exact clones (names drop out of the Type-2 hash); the third with an
# extra statement is a near-miss against the other two. Varying body length spreads
# them across the size bands the near-miss radius query walks. Fixed forever, so the
# `stages/*` numbers track the algorithms, not the input.
const SYNTH_N = 300

function synth_function(name::AbstractString, len::Int, extra::Bool)
    io = IOBuffer()
    println(io, "function $name(x)")
    println(io, "    a0 = x")
    for k in 1:len
        println(io, "    a$k = a$(k - 1) + $k")
    end
    extra && println(io, "    a0 = a0 * 2")
    println(io, "    return a$len")
    println(io, "end")
    return String(take!(io))
end

const SYNTH_DIR = let dir = mktempdir()
    for i in 1:SYNTH_N
        len = 12 + (i % 8) * 4
        extra = i % 3 == 0
        write(joinpath(dir, "f$(i).jl"), synth_function("f$(i)", len, extra))
    end
    dir
end

const SYNTH_FILES = Dendro.parse_corpus(Dendro.source_files(SYNTH_DIR))
const SYNTH_TABLE = Dendro.corpus_symbols(SYNTH_FILES)
const SYNTH_GRAPH = Dendro.build_corpus_graph(SYNTH_FILES, SYNTH_TABLE)

# === Clustering passes over the synthetic corpus ===
SUITE["stages"] = BenchmarkTools.BenchmarkGroup()
SUITE["stages"]["baseline"] =
    BenchmarkTools.@benchmarkable Dendro.baseline_from($SYNTH_FILES)
SUITE["stages"]["clones_exact"] =
    BenchmarkTools.@benchmarkable Dendro.cluster_duplicates($SYNTH_FILES)
SUITE["stages"]["clones_near"] =
    BenchmarkTools.@benchmarkable Dendro.cluster_near_duplicates($SYNTH_FILES)
SUITE["stages"]["naturalness"] =
    BenchmarkTools.@benchmarkable Dendro.cluster_unnatural($SYNTH_FILES)
SUITE["stages"]["corpus_graph"] =
    BenchmarkTools.@benchmarkable Dendro.build_corpus_graph($SYNTH_FILES, $SYNTH_TABLE)
SUITE["stages"]["cohesion"] =
    BenchmarkTools.@benchmarkable Dendro.cluster_low_cohesion($SYNTH_FILES, $SYNTH_GRAPH)
