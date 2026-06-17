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
    oldleft = 0
    newleft = 0
    for ln in eachline(IOBuffer(diff))
        # A body line always carries a `+`/`-`/space prefix, so a line starting
        # with `@@` is a hunk header wherever it appears. The header's line
        # counts, not a line's text, then decide where the body ends, so body
        # content that resembles a `+++` header is read by its column alone.
        if startswith(ln, "@@")
            m = match(r"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", ln)
            curnew = parse(Int, m.captures[2])
            oldleft = m.captures[1] === nothing ? 1 : parse(Int, m.captures[1])
            newleft = m.captures[3] === nothing ? 1 : parse(Int, m.captures[3])
        elseif oldleft > 0 || newleft > 0
            c = isempty(ln) ? ' ' : ln[1]
            if c == '+'
                push!(get!(() -> Int[], added, file), curnew)
                curnew += 1
                newleft -= 1
            elseif c == '-'
                oldleft -= 1
            elseif c == '\\'
                # "\ No newline at end of file": not a content line.
            else
                curnew += 1
                oldleft -= 1
                newleft -= 1
            end
        elseif startswith(ln, "+++ ")
            path = ln[5:end]
            file = startswith(path, "b/") ? path[3:end] : path
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
