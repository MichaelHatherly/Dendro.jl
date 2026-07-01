# Shared threading primitives for the corpus-wide fan-outs. Base Julia Threads only.
# Every parallel path writes into a preallocated indexed output, folds per-item results in
# index order through `parallel_flatmap`, or merges then sorts, so a run's findings are
# byte-identical to the serial path at any thread count. Each fan-out falls back to serial
# below an item-count threshold: a small diff or single-file gate is compile-bound, and
# task overhead would only slow it.

# Item count at or above which a fan-out runs across threads.
const PARALLEL_MIN = 8

# Whether a fan-out of `n` items should run across threads.
parallel_enabled(n::Integer) = Threads.nthreads() > 1 && n >= PARALLEL_MIN

# Number of chunks a fan-out of `n` items splits into: one per thread when parallel, else one.
n_chunks(n::Integer) = parallel_enabled(n) ? min(Threads.nthreads(), n) : 1

# Round-robin partition of `1:n` into `nc` strided ranges. Round-robin spreads heavy items
# (large files or functions) across chunks, so one outlier does not skew a contiguous chunk.
chunk_indices(n::Integer, nc::Integer) = [c:nc:n for c in 1:nc]

# Spawn one task per chunk and wait for all of them. A failed task's own exception is
# rethrown, not the `TaskFailedException` wrapper, so an error inside a fan-out surfaces
# identically to the serial path at any thread count and corpus size.
function spawn_chunks(work!::F, chunks) where {F}
    tasks = [Threads.@spawn work!(c, chunks[c]) for c in eachindex(chunks)]
    failed = nothing
    for t in tasks
        try
            wait(t)
        catch e
            e isa TaskFailedException || rethrow()
            failed === nothing && (failed = e.task)
        end
    end
    failed === nothing || throw(failed.result)
    return nothing
end

# Store `f(i)` at `out[i]` for each index of `out`, across threads when the item count
# clears the threshold. `f` must be thread-safe: shared reads only, writes confined to its
# return value.
function parallel_map!(f::F, out::AbstractVector) where {F}
    n = length(out)
    parallel_enabled(n) || return map_range!(f, out, 1:n)
    spawn_chunks((c, idxs) -> map_range!(f, out, idxs), chunk_indices(n, n_chunks(n)))
    return out
end

# Named worker so the hot loop is a concrete method (function barrier), never a boxed closure.
function map_range!(f::F, out::AbstractVector, idxs) where {F}
    for i in idxs
        out[i] = f(i)
    end
    return out
end

# The concatenation of `f(i)::Vector{T}` over `1:n`, computed across threads when the item
# count clears the threshold and folded in index order. Owning the fold here keeps the
# ordering half of the determinism invariant in one place instead of at every fan-out.
function parallel_flatmap(f::F, n::Integer, ::Type{T}) where {F, T}
    perindex = Vector{Vector{T}}(undef, n)
    parallel_map!(f, perindex)
    out = T[]
    for v in perindex
        append!(out, v)
    end
    return out
end

# Run `work!(state, idxs)` once per chunk, each chunk with its own `make_state()`, across
# threads when the item count clears the threshold. Returns the per-chunk states in chunk
# order. For fan-outs that carry per-chunk state (a parser pool, a partial baseline) rather
# than one value per item.
function parallel_chunks(work!::F, make_state::G, n::Integer) where {F, G}
    chunks = chunk_indices(n, n_chunks(n))
    states = [make_state() for _ in chunks]
    if parallel_enabled(n)
        spawn_chunks((c, idxs) -> work!(states[c], idxs), chunks)
    else
        work!(states[1], chunks[1])
    end
    return states
end
