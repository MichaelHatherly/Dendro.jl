package corpus

// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

// dendro-expect: near_duplicate
func renderLeft(node *Node, depth int) string {
    pad := repeat("  ", depth)
    label := pad + node.name
    children := node.kids
    lines := []string{label}
    for i := 0; i < node.count; i++ {
        lines = append(lines, renderLeft(children[i], depth+1))
    }
    return join(lines, "\n")
}

// dendro-expect: near_duplicate
func renderRight(node *Node, depth int) string {
    pad := repeat("  ", depth)
    label := pad + node.title
    children := node.kids
    lines := []string{label}
    for i := 0; i < node.count; i++ {
        lines = append(lines, renderRight(children[i], depth+1))
    }
    sortStrings(lines)
    return join(lines, "\n")
}
