// A near-miss pair: the same shape bar one extra statement, clearing the similarity
// threshold without being exact.

// dendro-expect: near_duplicate
fn render_left(node: &Node, depth: i32) -> String {
    let pad = repeat("  ", depth);
    let label = pad + &node.name;
    let children = &node.kids;
    let mut lines = vec![label];
    for i in 0..node.count {
        lines.push(render_left(&children[i], depth + 1));
    }
    return join(&lines, "\n");
}

// dendro-expect: near_duplicate
fn render_right(node: &Node, depth: i32) -> String {
    let pad = repeat("  ", depth);
    let label = pad + &node.title;
    let children = &node.kids;
    let mut lines = vec![label];
    for i in 0..node.count {
        lines.push(render_right(&children[i], depth + 1));
    }
    lines.sort();
    return join(&lines, "\n");
}
