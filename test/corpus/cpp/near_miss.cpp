// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

// dendro-expect: near_duplicate
std::string render_left(Node *node, int depth) {
    std::string pad = repeat("  ", depth);
    std::string label = pad + node->name;
    auto children = node->kids;
    StrList lines = list_of(label);
    for (int i = 0; i < node->count; i++) {
        lines.push_back(render_left(children[i], depth + 1));
    }
    return join(lines, "\n");
}

// dendro-expect: near_duplicate
std::string render_right(Node *node, int depth) {
    std::string pad = repeat("  ", depth);
    std::string label = pad + node->title;
    auto children = node->kids;
    StrList lines = list_of(label);
    for (int i = 0; i < node->count; i++) {
        lines.push_back(render_right(children[i], depth + 1));
    }
    sort_lines(lines);
    return join(lines, "\n");
}
