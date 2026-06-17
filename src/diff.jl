# Diff-scoping. Score only the functions a change touched, the "did this edit
# make things worse" question, rather than the whole file.

intersects(ranges::Vector{UnitRange{Int}}, a::Int, b::Int) =
    any(r -> a <= last(r) && b >= first(r), ranges)

inrange(ranges::Vector{UnitRange{Int}}, line::Int) = any(r -> line in r, ranges)

# Merge sorted line numbers into contiguous ranges.
function coalesce_lines(lines::Vector{Int})
    isempty(lines) && return UnitRange{Int}[]
    sorted = sort(unique(lines))
    ranges = UnitRange{Int}[]
    start = prev = sorted[1]
    for x in sorted[2:end]
        if x == prev + 1
            prev = x
        else
            push!(ranges, start:prev)
            start = prev = x
        end
    end
    push!(ranges, start:prev)
    return ranges
end

"""
    changed_ranges(diff) -> Dict{String,Vector{UnitRange{Int}}}

Parse a unified diff into the new-file line ranges that each file added or
changed, keyed by the new path.
"""
function changed_ranges(diff::AbstractString)
    added = Dict{String,Vector{Int}}()
    file = ""
    curnew = 0
    for ln in eachline(IOBuffer(diff))
        if startswith(ln, "+++ ")
            path = ln[5:end]
            file = startswith(path, "b/") ? path[3:end] : path
        elseif startswith(ln, "--- ") || startswith(ln, "diff --git") || startswith(ln, "index ")
            # file headers, no line content
        elseif startswith(ln, "@@")
            m = match(r"\+(\d+)", ln)
            curnew = parse(Int, m.captures[1])
        elseif startswith(ln, "+")
            push!(get!(() -> Int[], added, file), curnew)
            curnew += 1
        elseif startswith(ln, "-") || startswith(ln, "\\")
            # deletion or no-newline marker, no new-file advance
        else
            # context line
            curnew += 1
        end
    end
    return Dict(f => coalesce_lines(ls) for (f, ls) in added)
end

"""
    analyze_diff(; repo=pwd(), base="HEAD", baseline=nothing, cut=0.95) -> Vector{Finding}

Report findings only for functions touched by the diff of `repo` against
`base`. Changed files are read from the working tree and scored within their
changed line ranges.
"""
function analyze_diff(; repo = pwd(), base = "HEAD", baseline = nothing, cut::Real = 0.95)
    diff = read(`git -C $repo diff $base`, String)
    out = Finding[]
    for (relpath, ranges) in changed_ranges(diff)
        lang = language_for_path(relpath)
        (lang === nothing || !haskey(PROFILES, lang)) && continue
        full = joinpath(repo, relpath)
        isfile(full) || continue
        profile = PROFILES[lang]
        source = read(full, String)
        tree = parse(parser_for(lang), source)
        dirs = suppressions(tree, profile, source; file = relpath)
        scan = Scan(profile, source, relpath; baseline, cut, within = ranges, directives = dirs)
        append!(out, findings_for_tree(tree, scan))
    end
    return out
end
