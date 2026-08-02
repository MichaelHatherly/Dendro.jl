# Diff-scoping. Score only the functions a change touched, the "did this edit
# make things worse" question, rather than the whole file. The line numbers a scope is
# built from come from `git.jl`; this is the vocabulary they are expressed in.

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
