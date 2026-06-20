// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

class RenderOps {
    // dendro-expect: near_duplicate
    String renderLeft(Node node, int depth) {
        String pad = repeat("  ", depth);
        String label = pad + node.name;
        Node[] children = node.kids;
        StrList lines = listOf(label);
        for (int i = 0; i < node.count; i++) {
            lines.push(renderLeft(children[i], depth + 1));
        }
        return join(lines, "\n");
    }

    // dendro-expect: near_duplicate
    String renderRight(Node node, int depth) {
        String pad = repeat("  ", depth);
        String label = pad + node.title;
        Node[] children = node.kids;
        StrList lines = listOf(label);
        for (int i = 0; i < node.count; i++) {
            lines.push(renderRight(children[i], depth + 1));
        }
        sortLines(lines);
        return join(lines, "\n");
    }
}
