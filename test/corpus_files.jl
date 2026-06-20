@testitem "corpus findings match expectation markers" setup = [Fixtures] tags = [:corpus_files] begin
    @testset "$lang" for lang in Fixtures.corpus_langs()
        mm = Fixtures.corpus_mismatch(lang)
        @test mm.unexpected == String[]   # findings with no marker
        @test mm.missing == String[]      # markers with no finding
    end
end

@testitem "corpus analysis holds its invariants" setup = [Fixtures] tags = [:corpus_files] begin
    using Dendro: analyze, functions, source_files, language_for_path

    @testset "$lang" for lang in Fixtures.corpus_langs()
        dir = joinpath(Fixtures.corpus_root(), string(lang))

        # Deterministic: two runs over the same corpus agree.
        sites(fs) = sort([(f.metric, loc.file, loc.line) for f in fs for loc in f.locations])
        @test sites(analyze(dir; cut = 2.0)) == sites(analyze(dir; cut = 2.0))

        nlines = Dict(p => length(readlines(p)) for p in source_files(dir))
        for f in analyze(dir; cut = 2.0), loc in f.locations
            @test 1 <= loc.line <= nlines[loc.file]    # finding line within the file
        end

        for path in source_files(dir)
            i = Fixtures.idx(language_for_path(path), read(path, String))
            for u in functions(i)
                @test Dendro.cyclomatic(u.node, i) >= 1
                @test Dendro.nesting_depth(u.node, i) >= 0
                @test Dendro.parameter_count(u.node, i) >= 0
            end
        end
    end
end
