# A near-miss pair: the same shape bar one extra statement and a renamed field, so
# they clear the similarity threshold without being exact.

# dendro-expect: near_duplicate
def render_left(node, depth):
    pad = "  " * depth
    label = pad + node.name
    children = node.kids
    lines = [label]
    for kid in children:
        lines.append(render_left(kid, depth + 1))
    return "\n".join(lines)


# dendro-expect: near_duplicate
def render_right(node, depth):
    pad = "  " * depth
    label = pad + node.title
    children = node.kids
    lines = [label]
    for kid in children:
        lines.append(render_right(kid, depth + 1))
    lines.sort()
    return "\n".join(lines)
