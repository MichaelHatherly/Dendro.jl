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

# The on-disk layout of a serialized index. Bumped whenever `RefAnchor` or `ReferenceIndex`
# changes shape, so an entry written by an older Dendro is a miss rather than a wrong answer.
const REFERENCE_FORMAT = 1

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
        name == REFERENCE_SWEEP_STAMP && continue
        path = joinpath(dir, name)
        isfile(path) && now - mtime(path) > max_age &&
            best_effort(() -> rm(path; force = true), "removing a stale cache entry")
    end
    return nothing
end

# A cached index, or `nothing` when the cache cannot answer. Every failure is a miss: a
# missing entry, a truncated write, an entry another version of Julia serialized, a file
# something else left in the directory. A cache is an optimisation and must not be able to
# break a scan.
#
# A hit is touched, since `sweep_references` reads time since last use: without it a cache
# a project has warmed daily for months still expires. Touching is guarded on its own, so a
# read-only cache directory still serves the hit it just read.
function load_reference(key::String)::Union{ReferenceIndex, Nothing}
    path = joinpath(reference_cache_dir(), key)
    isfile(path) || return nothing
    loaded = try
        open(Serialization.deserialize, path)
    catch err
        @debug "Dendro: unreadable reference cache entry, rebuilding" path exception = err
        return nothing
    end
    loaded isa ReferenceIndex || return nothing
    best_effort(() -> touch(path), "recording cache use")
    return loaded
end

# Write one index to the cache, best effort. Serialized to a temporary file in the same
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
            Serialization.serialize(io, index)
            close(io)
            mv(tmp, joinpath(dir, key); force = true)
        finally
            rm(tmp; force = true)
        end
        sweep_references(dir)
    end
    return nothing
end
