# A near-miss pair: the same flat sequence bar one extra statement, clearing the
# similarity threshold without being exact.

# dendro-expect: near_duplicate
def render_left(node, depth)
  pad = "  " * depth
  head = pad + node.name
  body = pad + node.summary
  foot = pad + node.footer
  size = head.length + body.length
  parts = [head, body, foot]
  count = parts.length
  parts.join("\n")
end

# dendro-expect: near_duplicate
def render_right(node, depth)
  pad = "  " * depth
  head = pad + node.name
  body = pad + node.summary
  foot = pad + node.footer
  size = head.length + body.length
  parts = [head, body, foot]
  count = parts.length
  parts.reverse!
  parts.join("\n")
end
