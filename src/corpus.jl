# Gathering a corpus. Resolving roots into a set of paths, and parsing each path once
# into the `ParsedFile` records every later pass reads. What runs over those records
# lives in `analyze.jl`.

# Parse each path once. Each record carries everything the baseline, the per-file
# scoring pass, and duplicate clustering need, so no file is parsed twice. Files
# whose language has no profile are skipped. `language` forces one language for
# every path, as `analyze` does.
function parse_corpus(
        paths::AbstractVector{<:AbstractString}; language = nothing,
        rules = BUILTIN_RULES, profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    forced = language === nothing ? nothing : Symbol(lowercase(String(language)))
    extensions = extension_map(profiles)
    entries = Tuple{String, LanguageProfile}[]
    for path in paths
        lang = forced === nothing ? language_for_path(path, extensions) : forced
        lang === nothing && continue
        haskey(profiles, lang) || continue
        push!(entries, (String(path), profiles[lang]))
    end
    n = length(entries)
    files = Vector{ParsedFile}(undef, n)
    # Warm every language's caches up front, so no parse task pays a grammar load or a
    # query compile mid fan-out; this also leaves the imports query warm for the linkage
    # passes.
    warm_languages(unique(last(e) for e in entries))
    parallel_chunks(() -> Dict{LanguageProfile, TreeSitter.Parser}(), n) do parsers, idxs
        parse_chunk!(files, parsers, entries, idxs, rules)
    end
    # A file the parse boundary turned away leaves its slot unassigned. Compacting in index
    # order keeps the corpus order every later pass and the parallel determinism rely on.
    return ParsedFile[files[i] for i in 1:n if isassigned(files, i)]
end

# Parse one chunk of files with the chunk's parser pool: a `TreeSitter.Parser` is stateful,
# so each chunk keeps its own, reused across its files. Writes into the shared preallocated
# `files` at each entry's index, so the corpus order matches the serial path. A file the
# parser cannot take leaves its slot unassigned and `parse_corpus` drops it.
function parse_chunk!(
        files::Vector{ParsedFile}, parsers::Dict{LanguageProfile, TreeSitter.Parser},
        entries::Vector{Tuple{String, LanguageProfile}}, idxs, rules
    )
    for i in idxs
        path, profile = entries[i]
        source = read(path, String)
        # Tree-sitter takes the source as a C string, so a byte no C string can carry is a
        # file the parser will never accept. A corpus holds such a file now and then, a
        # fuzzer test case checked in beside real source, and one of them must not take the
        # whole scan down. Report it and carry on, the honest-over-silent reading: naming the
        # file is what tells a skipped file from a clean one.
        if occursin('\0', source)
            @warn "Dendro: skipping a file with an embedded NUL byte, which cannot be parsed" path
            continue
        end
        parser = get!(() -> parser_for(profile), parsers, profile)
        tree = parse(parser, source)
        index = build_index(tree, profile.name, source, query_for(profile), scopes_query_for(profile))
        directives = suppressions(index; file = path, rules)
        files[i] = ParsedFile(profile, source, path, tree, index, directives)
    end
    return nothing
end

# Recurse a directory for files Dendro can analyze, pruning dot-directories like
# `.git` and keeping only files whose extension resolves to a language profile.
# `ignore` patterns, matched against each path relative to `dir`, prune directories
# and drop files before they reach the corpus, so vendored source never feeds the
# baseline.
function source_files(
        dir::AbstractString, ignore = String[];
        profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    patterns = compile_ignores(ignore)
    extensions = extension_map(profiles)
    files = String[]
    for (root, dirs, names) in walkdir(dir)
        filter!(dirs) do d
            !startswith(d, ".") && !is_ignored(patterns, relpath(joinpath(root, d), dir), true)
        end
        for name in names
            lang = language_for_path(name, extensions)
            (lang === nothing || !haskey(profiles, lang)) && continue
            is_ignored(patterns, relpath(joinpath(root, name), dir), false) && continue
            push!(files, joinpath(root, name))
        end
    end
    return files
end

# Resolve a list of roots into the unique set of file paths to parse. A directory is
# walked for analyzable source under `ignore`; a named file is taken as-is, but only
# when its language can be inferred or `language` forces one. The shared front of
# `analyze` and `mermaid`, so both see the same corpus from the same roots.
function collect_corpus(
        roots::Vector{String}, ignore, language;
        profiles::Dict{Symbol, LanguageProfile} = PROFILES
    )
    isempty(roots) && error("Dendro: no paths given")
    extensions = extension_map(profiles)
    corpus = String[]
    for path in roots
        ispath(path) || error("Dendro: no such path $path")
        if isdir(path)
            append!(corpus, source_files(path, ignore; profiles))
        else
            language === nothing && language_for_path(path, extensions) === nothing &&
                error("Dendro: cannot infer language for $path; pass `language=`.")
            push!(corpus, path)
        end
    end
    unique!(corpus)
    return corpus
end
