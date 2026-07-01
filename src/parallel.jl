# Shared threading primitives for the corpus-wide fan-outs. Base Julia Threads only.
# Every parallel path writes into a preallocated indexed output or merges then sorts, so a
# run's findings are byte-identical to the serial path at any thread count. Below a corpus
# size threshold the serial path runs: a diff or single-file gate is compile-bound, and task
# overhead would only slow it.

# Corpus size at or above which a fan-out runs across threads.
const PARALLEL_MIN = 8

# Whether a fan-out of `n` items should run across threads.
parallel_enabled(n::Integer) = Threads.nthreads() > 1 && n >= PARALLEL_MIN

# Number of chunks a fan-out of `n` items splits into: one per thread when parallel, else one.
n_chunks(n::Integer) = parallel_enabled(n) ? min(Threads.nthreads(), n) : 1

# Round-robin partition of `1:n` into `nc` index vectors. Round-robin spreads heavy items
# (large files or functions) across chunks, so one outlier does not skew a contiguous chunk.
function chunk_indices(n::Integer, nc::Integer)
    chunks = [Int[] for _ in 1:nc]
    for i in 1:n
        push!(chunks[mod1(i, nc)], i)
    end
    return chunks
end

# Store `f(i)` at `out[i]` for each `i in 1:n`, across threads when the corpus clears the
# threshold. `f` must be thread-safe: shared reads only, writes confined to its return value.
function parallel_map!(f::F, out::AbstractVector, n::Integer) where {F}
    parallel_enabled(n) || return map_range!(f, out, 1:n)
    @sync for idxs in chunk_indices(n, n_chunks(n))
        Threads.@spawn map_range!(f, out, idxs)
    end
    return out
end

# Named worker so the hot loop is a concrete method (function barrier), never a boxed closure.
function map_range!(f::F, out::AbstractVector, idxs) where {F}
    for i in idxs
        out[i] = f(i)
    end
    return out
end
