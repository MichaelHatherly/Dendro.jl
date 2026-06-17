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

# Effect of one diff body line, read from its prefix char: whether it is an added
# line, and the step to the new-side cursor and the remaining old/new hunk counts. A
# `\` line ("\ No newline at end of file") is not content and moves nothing.
function body_line_effect(c::Char)
    c == '+' && return (added = true, cur = 1, old = 0, new = -1)
    c == '-' && return (added = false, cur = 0, old = -1, new = 0)
    c == '\\' && return (added = false, cur = 0, old = 0, new = 0)
    return (added = false, cur = 1, old = -1, new = -1)
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
            e = body_line_effect(isempty(ln) ? ' ' : ln[1])
            e.added && push!(get!(() -> Int[], added, file), curnew)
            curnew += e.cur
            oldleft += e.old
            newleft += e.new
        elseif startswith(ln, "+++ ")
            path = ln[5:end]
            file = startswith(path, "b/") ? path[3:end] : path
        end
    end
    return Dict(f => coalesce_lines(ls) for (f, ls) in added)
end
