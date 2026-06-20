<?php

// A near-miss pair: the same flat sequence bar one extra statement, clearing the
// similarity threshold without being exact. A flat body keeps any shared sub-block
// below the clone anchor floor, so only the whole-function near-miss is reported.

// dendro-expect: near_duplicate
function render_left($node, $depth) {
    $pad = str_repeat("  ", $depth);
    $head = $pad . $node->name;
    $body = $pad . $node->summary;
    $foot = $pad . $node->footer;
    $size = strlen($head) + strlen($body);
    $parts = array($head, $body, $foot);
    $count = count($parts);
    return implode("\n", $parts);
}

// dendro-expect: near_duplicate
function render_right($node, $depth) {
    $pad = str_repeat("  ", $depth);
    $head = $pad . $node->name;
    $body = $pad . $node->summary;
    $foot = $pad . $node->footer;
    $size = strlen($head) + strlen($body);
    $parts = array($head, $body, $foot);
    $count = count($parts);
    $parts = array_reverse($parts);
    return implode("\n", $parts);
}
