// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

// dendro-expect: near_duplicate
function renderLeft(node, depth) {
    let pad = "  ".repeat(depth);
    let label = pad + node.name;
    let children = node.kids;
    let lines = [label];
    for (let i = 0; i < node.count; i++) {
        lines.push(renderLeft(children[i], depth + 1));
    }
    return lines.join("\n");
}

// dendro-expect: near_duplicate
function renderRight(node, depth) {
    let pad = "  ".repeat(depth);
    let label = pad + node.title;
    let children = node.kids;
    let lines = [label];
    for (let i = 0; i < node.count; i++) {
        lines.push(renderRight(children[i], depth + 1));
    }
    sortLines(lines);
    return lines.join("\n");
}
