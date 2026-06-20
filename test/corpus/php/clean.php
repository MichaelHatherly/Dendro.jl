<?php

// Cohesive: each function calls the next, so the file is one connected component.

const LO = 0.0;
const HI = 1.0;

function clampv($x, $lo, $hi) {
    if ($x < $lo) {
        return $lo;
    }
    if ($x > $hi) {
        return $hi;
    }
    return $x;
}

function normalize($x) {
    return clampv($x, LO, HI);
}

function scale($x, $k) {
    return normalize($x) * $k;
}

function accumulate($xs) {
    $total = 0.0;
    for ($i = 0; $i < count($xs); $i++) {
        $total += scale($xs[$i], 2);
    }
    return $total;
}
