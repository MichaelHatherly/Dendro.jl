// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

// dendro-expect: near_duplicate
char *render_left(Node *node, int depth) {
    char *pad = repeat("  ", depth);
    char *label = concat(pad, node->name);
    Node **children = node->kids;
    StrList lines = list_of(label);
    for (int i = 0; i < node->count; i++) {
        list_push(lines, render_left(children[i], depth + 1));
    }
    return join(lines, "\n");
}

// dendro-expect: near_duplicate
char *render_right(Node *node, int depth) {
    char *pad = repeat("  ", depth);
    char *label = concat(pad, node->title);
    Node **children = node->kids;
    StrList lines = list_of(label);
    for (int i = 0; i < node->count; i++) {
        list_push(lines, render_right(children[i], depth + 1));
    }
    list_sort(lines);
    return join(lines, "\n");
}
