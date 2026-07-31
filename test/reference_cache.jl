@testitem "a reference index round-trips through its own format" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = [
                "Dep.jl" => Fixtures.libmod(
                    ["partition"],
                    Fixtures.chain("partition", 8) * Fixtures.nested_chain("hidden", 7),
                ),
            ],
        )
        index = Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 10, cache = false)

        # Both flags have to vary across the fixture's anchors, or a swapped bit passes.
        # `public` is what promotes a finding into the gate, so a swap would gate on the
        # private matches and stay quiet about the importable ones.
        @test any(a -> a.public, index.anchors)
        @test any(a -> !a.public, index.anchors)
        @test any(a -> a.whole_unit, index.anchors)
        @test any(a -> !a.whole_unit, index.anchors)

        # `RefAnchor` holds a vector and a dictionary, so the default `==` compares them by
        # identity. Project to a tuple and the comparison is by value, field by field.
        fields(a) = (
            a.language, a.hash, a.size, a.sequence, a.histogram,
            a.whole_unit, a.symbol, a.public, a.file, a.line,
        )

        back = Dendro.decode_index(Dendro.encode_index(index))
        @test back.library == index.library
        @test back.grain == index.grain
        @test fields.(back.anchors) == fields.(index.anchors)
        # Neither table is written; both are rebuilt from the anchors on read, in the order
        # `build_reference_index` built them.
        @test back.by_hash == index.by_hash
        @test back.units == index.units
    end
end

@testitem "one index encodes to the same bytes every time" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )
        index = Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 10, cache = false)

        # A histogram is a dictionary, so its iteration order is arbitrary and an encoder
        # that followed it would write a different entry each run. Keys go in sorted, which
        # is what makes an entry comparable with itself.
        @test Dendro.encode_index(index) == Dendro.encode_index(index)
    end
end

@testitem "an anchor-grain index round-trips its block features" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.nested_chain("partition", 8))],
        )
        index = Dendro.reference_index(
            Dendro.Library("Dep", lib); min_size = 10, grain = :anchor, cache = false
        )

        # At this grain every anchor carries near-miss features, including the blocks the
        # unit grain leaves bare. Those are what the wider near pass reads, so losing them
        # in a round-trip would under-report rather than fail.
        @test any(a -> !a.whole_unit, index.anchors)
        @test all(a -> !isempty(a.sequence), index.anchors)

        back = Dendro.decode_index(Dendro.encode_index(index))
        @test back.grain == :anchor
        @test [a.sequence for a in back.anchors] == [a.sequence for a in index.anchors]
        @test [a.histogram for a in back.anchors] == [a.histogram for a in index.anchors]
    end
end

@testitem "an index with no anchors round-trips" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 6))],
        )
        # A floor nothing in the fixture clears, which is how a library of small helpers
        # indexes to nothing at all.
        index = Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 200, cache = false)
        @test isempty(index.anchors)

        back = Dendro.decode_index(Dendro.encode_index(index))
        @test isempty(back.anchors)
        @test isempty(back.units)
        @test isempty(back.by_hash)
        @test back.library == "Dep"
    end
end

@testitem "a non-ASCII symbol and file name survive a round-trip" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dép.jl" => Fixtures.libmod(["münze"], Fixtures.chain("münze", 8))],
        )
        index = Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 10, cache = false)

        back = Dendro.decode_index(Dendro.encode_index(index))
        # A string is length-prefixed in bytes and not in characters, and the two differ for
        # both of these names.
        @test [a.symbol for a in back.anchors] == [a.symbol for a in index.anchors]
        @test [a.file for a in back.anchors] == [a.file for a in index.anchors]
        @test any(a -> a.symbol == "münze", back.anchors)
        @test any(a -> a.file == "Dép.jl", back.anchors)
    end
end

@testitem "an entry that is not a reference index is refused" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )
        good = Dendro.encode_index(
            Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 10, cache = false)
        )

        # The magic is the first thing read, so a file something else left in the cache
        # directory is refused before a single length prefix is trusted.
        wrong_magic = copy(good)
        wrong_magic[1] = 0x00
        @test_throws ErrorException Dendro.decode_index(wrong_magic)

        # The version follows the magic. An entry written to a layout this Dendro does not
        # know is refused rather than read against the layout it does.
        future = copy(good)
        future[length(Dendro.REFERENCE_MAGIC) + 1] = 0xff
        @test_throws ErrorException Dendro.decode_index(future)

        @test_throws ErrorException Dendro.decode_index(UInt8[])
    end
end

@testitem "a truncated reference index is refused wherever it is cut" setup = [Fixtures] tags = [:libraries] begin
    mktempdir() do dir
        _, lib = Fixtures.library_corpus(
            dir;
            project = ["util.jl" => Fixtures.chain("chunk_by", 6)],
            library = ["Dep.jl" => Fixtures.libmod(["partition"], Fixtures.chain("partition", 8))],
        )
        good = Dendro.encode_index(
            Dendro.reference_index(Dendro.Library("Dep", lib); min_size = 10, cache = false)
        )

        # The interesting cuts are mid-record, inside a length-prefixed run, so this walks
        # the whole buffer rather than picking an offset and hoping it is one of them.
        @testset "cut to $n bytes" for n in 0:7:(length(good) - 1)
            @test_throws ErrorException Dendro.decode_index(good[1:n])
        end
    end
end

@testitem "a reference index cannot ask for memory it does not hold" tags = [:libraries] begin
    # The layout written out by hand, so this item can hand the reader bytes the encoder
    # cannot produce. Restating the format here is the point: a parser earns its keep
    # against input its own writer would never make.
    function crafted(; poolsize = 1, library = 1, seqlen = 0)
        io = IOBuffer()
        write(io, Dendro.REFERENCE_MAGIC)
        write(io, htol(UInt32(Dendro.REFERENCE_FORMAT)))
        write(io, htol(UInt32(poolsize)))
        write(io, htol(UInt32(5)))
        write(io, b"julia")
        write(io, UInt8(1))              # :unit, the first LIBRARY_GRAINS entry
        write(io, htol(UInt32(library)))
        write(io, htol(UInt32(1)))       # one anchor
        write(io, htol(UInt32(1)))       # language
        write(io, htol(UInt64(0)))       # hash
        write(io, htol(UInt32(1)))       # size
        write(io, UInt8(1))              # whole_unit, not public
        write(io, htol(UInt32(1)))       # symbol
        write(io, htol(UInt32(1)))       # file
        write(io, htol(UInt32(1)))       # line
        write(io, htol(UInt32(seqlen)))  # what the anchor claims to carry
        write(io, htol(UInt32(0)))       # and an empty histogram, so an honest one is whole
        return take!(io)
    end

    # The reader has to refuse before it allocates. This entry claims four billion sequence
    # entries in a file of ninety bytes, and believing it is a 34 GB request. This is the
    # item the format exists for: `Serialization` had no way to make the promise.
    @test_throws ErrorException Dendro.decode_index(crafted(seqlen = typemax(UInt32)))

    # A pool position past the pool is the same class of fault as a length past the buffer,
    # and gets the same answer.
    @test_throws ErrorException Dendro.decode_index(crafted(library = 2))

    # The same bytes with an honest claim decode, so a refusal above is the check firing
    # rather than the fixture being malformed.
    @test Dendro.decode_index(crafted()) isa Dendro.ReferenceIndex
end
