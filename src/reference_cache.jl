# Where a parsed `ReferenceIndex` is kept between scans. Indexing a dependency set is the
# dominant cost of a cross-corpus scan and a dependency set changes rarely, so this is what
# keeps `:library_duplicate` and `:library_near_duplicate` usable on every CI run.
#
# One invariant runs through the file: a cache is an optimisation and must not be able to
# break a scan. Every failure is a miss and a rebuild rather than an error, whatever a stale
# entry, a truncated write, a read-only directory or a full disk does to it. `best_effort`
# is that invariant named once instead of restated at each site.
#
# Included after `libraries.jl`, whose `ReferenceIndex` it names in a signature. Only
# `reference_index` reads any of this, since only it decides whether to consult the cache.

# The cache directory: a scratch space namespaced to Dendro, which `Pkg.gc()` reclaims once
# Dendro itself is uninstalled. Entries inside a live space it never touches, which is what
# `sweep_references` is for.
#
# `DENDRO_CACHE_DIR` overrides it. An environment variable rather than a `.dendro.toml` key,
# since the config cascade carries flagging opinions and not paths, and rather than
# Scratch's own `with_scratch_directory`, since that sets an in-process binding and the
# suite spawns subprocesses that index libraries.
reference_cache_dir()::String = get(ENV, "DENDRO_CACHE_DIR") do
    Scratch.@get_scratch!("references")
end

# The on-disk layout an entry is written to. Bumped whenever `RefAnchor` or `ReferenceIndex`
# changes shape. It goes into the cache key and into the entry itself, so an entry written to
# a layout this Dendro does not know is both missed on lookup and refused on read, rather
# than read against the layout it does know.
const REFERENCE_FORMAT = 1

# The bytes an entry opens with. A file that does not start with these is not an index,
# whatever else it is, so reading stops before anything is sized from its content.
const REFERENCE_MAGIC = b"DENDROIX"

# What an anchor costs before its variable-length parts: three pool positions, the hash, the
# size, the flags, the line, and the two length prefixes. A count of anchors clears this
# before the vector exists, so a count off the wire cannot ask for more memory than the bytes
# present could justify.
const REFERENCE_ANCHOR_FIXED = 37

# How long an entry survives without being used. Entries are touched on every hit, so this
# reads time since last use rather than since creation: a dependency set scanned weekly
# stays warm and one scanned once is gone. With the sweep gated to a day an entry lives at
# most eight, and a project returned to fortnightly rebuilds cold, which is the trade.
const REFERENCE_MAX_AGE = 7 * 24 * 60 * 60

# How often the sweep runs at most, read off the stamp file's own mtime.
const REFERENCE_SWEEP_INTERVAL = 24 * 60 * 60

# The stamp's name. Entry names are hex digests, so it cannot collide with one.
const REFERENCE_SWEEP_STAMP = "last-sweep"

# What a cached index is keyed by: everything that could change the anchors it holds. The
# format and the two versions cover the serialized shape, `min_size` the floors an anchor
# had to clear, `grain` which anchors carry near-miss features, and the size and mtime of
# every indexed file the content itself. Paths go in in `collect_corpus` order, which is
# deterministic, so the same library keys the same way on every scan.
function reference_key(library::Library, paths::Vector{String}, min_size::Integer, grain::Symbol)
    h = hash(REFERENCE_FORMAT)
    h = hash(something(pkgversion(@__MODULE__), v"0"), h)
    h = hash(VERSION, h)
    h = hash(min_size, h)
    h = hash(grain, h)
    h = hash(library.name, h)
    for p in paths
        info = stat(p)
        h = hash((p, info.size, info.mtime), h)
    end
    return string(h; base = 16)
end

# The grain as one byte and back. `LIBRARY_GRAINS` is the enumeration, so its order is the
# encoding and a grain outside it cannot be named.
grain_code(grain::Symbol)::UInt8 = UInt8(something(findfirst(==(grain), LIBRARY_GRAINS)))

grain_at(code::Integer)::Symbol =
    1 <= code <= length(LIBRARY_GRAINS) ? LIBRARY_GRAINS[code] :
    error("Dendro: reference index names a grain that does not exist")

# The strings an index holds, interned, with the map from string to pool position. A `file`
# repeats once per anchor in that file, a `symbol` once per anchor in that definition, and
# every histogram key is a node type drawn from a vocabulary of a few dozen, so the pool is
# where nearly all of an entry's size saving is. Positions are assigned in anchor order,
# which is deterministic, so one index encodes to the same bytes on every run.
function string_pool(index::ReferenceIndex)
    pool = String[]
    ids = Dict{String, Int}()
    intern!(pool, ids, index.library)
    for a in index.anchors
        intern!(pool, ids, String(a.language))
        intern!(pool, ids, a.symbol)
        intern!(pool, ids, a.file)
        for t in sort!(collect(keys(a.histogram)))
            intern!(pool, ids, t)
        end
    end
    return pool, ids
end

intern!(pool::Vector{String}, ids::Dict{String, Int}, s::String) =
    get!(() -> (push!(pool, s); length(pool)), ids, s)

"""
    encode_index(index) -> Vector{UInt8}

One [`ReferenceIndex`](@ref) as the bytes a cache entry holds: a magic, the format version,
the interned string pool, the grain, the library name, and every anchor. Integers are
little-endian and fixed width, so an entry written on one machine reads on another.

`by_hash` and `units` are not written. Both are functions of `anchors`, and
[`decode_index`](@ref) rebuilds them in the order `build_reference_index` built them, so a
cache entry cannot hold a lookup table that disagrees with the anchors it indexes.
"""
function encode_index(index::ReferenceIndex)
    pool, ids = string_pool(index)
    io = IOBuffer()
    write(io, REFERENCE_MAGIC)
    write(io, htol(UInt32(REFERENCE_FORMAT)))
    write(io, htol(UInt32(length(pool))))
    for s in pool
        bytes = codeunits(s)
        write(io, htol(UInt32(length(bytes))))
        write(io, bytes)
    end
    write(io, grain_code(index.grain))
    write(io, htol(UInt32(ids[index.library])))
    write(io, htol(UInt32(length(index.anchors))))
    for a in index.anchors
        encode_anchor!(io, a, ids)
    end
    return take!(io)
end

# One anchor's fields in the order `decode_anchor` reads them. Histogram keys go in sorted,
# so the same anchor encodes to the same bytes whatever order its dictionary iterates.
function encode_anchor!(io::IO, a::RefAnchor, ids::Dict{String, Int})
    write(io, htol(UInt32(ids[String(a.language)])))
    write(io, htol(a.hash))
    write(io, htol(UInt32(a.size)))
    write(io, UInt8(a.whole_unit) | (UInt8(a.public) << 1))
    write(io, htol(UInt32(ids[a.symbol])))
    write(io, htol(UInt32(ids[a.file])))
    write(io, htol(UInt32(a.line)))
    write(io, htol(UInt32(length(a.sequence))))
    for h in a.sequence
        write(io, htol(h))
    end
    write(io, htol(UInt32(length(a.histogram))))
    for t in sort!(collect(keys(a.histogram)))
        write(io, htol(UInt32(ids[t])))
        write(io, htol(UInt32(a.histogram[t])))
    end
    return nothing
end

# A position in a byte buffer, and the one place a length read off the wire is checked
# against the bytes actually present. A cache entry is untrusted input: it may be truncated,
# left there by another tool, or crafted. Reading a count and allocating for it is how that
# becomes a crash, so every count clears `demand` before anything is sized from it.
mutable struct ByteCursor
    bytes::Vector{UInt8}
    pos::Int
end

ByteCursor(bytes::Vector{UInt8}) = ByteCursor(bytes, 1)

# Refuse to read past the end. Every failure here reaches `load_reference`, which reads it as
# a miss, so a malformed entry costs a rebuild rather than a scan.
demand(cur::ByteCursor, n::Int) =
    cur.pos + n - 1 <= length(cur.bytes) || error("Dendro: reference index ends mid-record")

function take_u8(cur::ByteCursor)
    demand(cur, 1)
    b = cur.bytes[cur.pos]
    cur.pos += 1
    return b
end

# Little-endian by construction rather than by `reinterpret`, so there is no alignment
# question and the same bytes read the same on any platform. The result is an `Int`: the
# arithmetic that follows a count is done in `Int` so a large count cannot wrap into a small
# one on its way to a bounds check.
function take_u32(cur::ByteCursor)
    demand(cur, 4)
    b, p = cur.bytes, cur.pos
    cur.pos += 4
    return Int(b[p]) | Int(b[p + 1]) << 8 | Int(b[p + 2]) << 16 | Int(b[p + 3]) << 24
end

function take_u64(cur::ByteCursor)
    demand(cur, 8)
    b, p = cur.bytes, cur.pos
    cur.pos += 8
    v = UInt64(0)
    for k in 0:7
        v |= UInt64(b[p + k]) << (8 * k)
    end
    return v
end

function take_string(cur::ByteCursor)
    n = take_u32(cur)
    demand(cur, n)
    s = String(cur.bytes[cur.pos:(cur.pos + n - 1)])
    cur.pos += n
    return s
end

# A pool position, checked against the pool it names. A position past the pool is the same
# class of fault as a length past the buffer, and gets the same answer.
function take_id(cur::ByteCursor, pool::Vector{String})
    i = take_u32(cur)
    1 <= i <= length(pool) || error("Dendro: reference index names a string it does not hold")
    return pool[i]
end

"""
    decode_index(bytes) -> ReferenceIndex

The [`ReferenceIndex`](@ref) `bytes` encode. Anything the format does not allow is an error:
a wrong magic, a version this Dendro does not write, a length reaching past the end of the
buffer, a pool position past the pool. [`load_reference`](@ref) reads every one of them as a
miss, so an entry that cannot be trusted costs a rebuild.

Nothing here constructs a type the bytes name, and no container is sized by a count that has
not been checked against the bytes present. That is what the format is Dendro's own for.
"""
function decode_index(bytes::Vector{UInt8})
    cur = ByteCursor(bytes)
    n = length(REFERENCE_MAGIC)
    demand(cur, n)
    view(cur.bytes, cur.pos:(cur.pos + n - 1)) == REFERENCE_MAGIC ||
        error("Dendro: not a reference index")
    cur.pos += n
    take_u32(cur) == REFERENCE_FORMAT || error("Dendro: reference index of another format")

    poolsize = take_u32(cur)
    # Every pool entry is at least its own length prefix, so this is the floor a claimed pool
    # size clears before the vector exists.
    demand(cur, 4 * poolsize)
    pool = Vector{String}(undef, poolsize)
    for i in 1:poolsize
        pool[i] = take_string(cur)
    end

    grain = grain_at(take_u8(cur))
    library = take_id(cur, pool)

    count = take_u32(cur)
    demand(cur, REFERENCE_ANCHOR_FIXED * count)
    anchors = Vector{RefAnchor}(undef, count)
    by_hash = Dict{Tuple{Symbol, UInt64}, Vector{Int}}()
    units = Int[]
    for i in 1:count
        a = decode_anchor(cur, pool)
        anchors[i] = a
        push!(get!(() -> Int[], by_hash, (a.language, a.hash)), i)
        a.whole_unit && push!(units, i)
    end
    return ReferenceIndex(library, by_hash, anchors, units, grain)
end

# One anchor, read in the order `encode_anchor!` wrote it. Both variable-length runs are
# demanded whole before their container is allocated, which is what keeps a count claiming
# four billion entries from asking for the memory to match.
function decode_anchor(cur::ByteCursor, pool::Vector{String})
    language = Symbol(take_id(cur, pool))
    digest = take_u64(cur)
    size = take_u32(cur)
    flags = take_u8(cur)
    symbol = take_id(cur, pool)
    file = take_id(cur, pool)
    line = take_u32(cur)

    seqlen = take_u32(cur)
    demand(cur, 8 * seqlen)
    sequence = Vector{UInt64}(undef, seqlen)
    for i in 1:seqlen
        sequence[i] = take_u64(cur)
    end

    histlen = take_u32(cur)
    demand(cur, 8 * histlen)
    histogram = Dict{String, Int}()
    sizehint!(histogram, histlen)
    for _ in 1:histlen
        # Both reads move the cursor, so the order they run in is the format. Written as
        # `histogram[take_id(cur, pool)] = take_u32(cur)` the value is evaluated first,
        # because that lowers to `setindex!(histogram, value, key)`, and the count is then
        # read where the pool position should be. Keep the two on separate lines.
        t = take_id(cur, pool)
        histogram[t] = take_u32(cur)
    end

    return RefAnchor(
        language, digest, size, sequence, histogram,
        flags & 0x01 != 0, symbol, flags & 0x02 != 0, file, line,
    )
end

# Filesystem work on the cache that must never surface. A read-only or full cache directory
# writes nothing and serves what it can, for the same reason a failed load is a miss: a
# cache is an optimisation and must not be able to break a scan.
function best_effort(f::F, what::AbstractString) where {F}
    try
        f()
    catch err
        @debug "Dendro: $what failed" exception = err
    end
    return nothing
end

# Delete entries no scan has wanted for `max_age`, at most once every `interval`. What
# accumulates is a dependency set nothing resolves to any more: the key folds in every
# indexed file's size and mtime, so one dependency bump orphans an entry permanently, and a
# scratch space is reclaimed only once Dendro itself is uninstalled, never per entry.
#
# The stamp is written before the sweep rather than after, so a process killed partway waits
# out the interval instead of re-sweeping on every write. Two processes sweeping at once is
# harmless: both only unlink, and unlinking a file another holds open for read is safe. Each
# removal is guarded on its own, so one failure does not abandon the rest of the pass.
function sweep_references(
        dir::String; max_age::Int = REFERENCE_MAX_AGE, interval::Int = REFERENCE_SWEEP_INTERVAL
    )
    stamp = joinpath(dir, REFERENCE_SWEEP_STAMP)
    now = time()
    isfile(stamp) && now - mtime(stamp) < interval && return nothing
    touch(stamp)
    for name in readdir(dir)
        # Entry names are hex digests, so anything else in the directory belongs to
        # something else. `DENDRO_CACHE_DIR` may name a directory Dendro does not own, and a
        # cache that deletes files it did not write has reached outside its own bargain.
        # This subsumes skipping the stamp, whose name is not hex.
        occursin(r"^[0-9a-f]+$", name) || continue
        path = joinpath(dir, name)
        isfile(path) && now - mtime(path) > max_age &&
            best_effort(() -> rm(path; force = true), "removing a stale cache entry")
    end
    return nothing
end

# A cached index, or `nothing` when the cache cannot answer. Every failure is a miss: a
# missing entry, a truncated write, an entry written to another layout, a file something else
# left in the directory. A cache is an optimisation and must not be able to break a scan.
#
# A hit is touched, since `sweep_references` reads time since last use: without it a cache
# a project has warmed daily for months still expires. Touching is guarded on its own, so a
# read-only cache directory still serves the hit it just read.
function load_reference(key::String)::Union{ReferenceIndex, Nothing}
    path = joinpath(reference_cache_dir(), key)
    isfile(path) || return nothing
    loaded = try
        decode_index(read(path))
    catch err
        @debug "Dendro: unreadable reference cache entry, rebuilding" path exception = err
        return nothing
    end
    best_effort(() -> touch(path), "recording cache use")
    return loaded
end

# Write one index to the cache, best effort. Encoded into a temporary file in the same
# directory and renamed, so a concurrent scan reads a whole entry or none. A read-only or
# full cache directory silently writes nothing, for the same reason a failed load is a miss.
#
# A write is also when the cache is swept, since it is the one point that already knows the
# directory exists and that something changed in it. `sweep_references` gates itself, so
# every write asking costs a `stat` of the stamp.
function store_reference(key::String, index::ReferenceIndex)
    dir = reference_cache_dir()
    best_effort("writing the reference cache") do
        mkpath(dir)
        tmp, io = mktemp(dir)
        try
            write(io, encode_index(index))
            close(io)
            mv(tmp, joinpath(dir, key); force = true)
        finally
            rm(tmp; force = true)
        end
        sweep_references(dir)
    end
    return nothing
end
