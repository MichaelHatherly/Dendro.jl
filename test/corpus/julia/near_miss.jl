# A near-miss pair: two renderers that are the copy-paste-then-edit case. They share
# the same shape bar one extra statement and a renamed field, so they clear the
# similarity threshold without being exact, reported as `:near_duplicate`.

# dendro-expect: near_duplicate
function render_left(node, depth)
    pad = repeat("  ", depth)
    label = pad * node.name
    children = node.kids
    lines = [label]
    for kid in children
        push!(lines, render_left(kid, depth + 1))
    end
    return join(lines, "\n")
end

# dendro-expect: near_duplicate
function render_right(node, depth)
    pad = repeat("  ", depth)
    label = pad * node.title
    children = node.kids
    lines = [label]
    for kid in children
        push!(lines, render_right(kid, depth + 1))
    end
    sort!(lines)
    return join(lines, "\n")
end
