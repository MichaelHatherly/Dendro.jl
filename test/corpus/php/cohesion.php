<?php

// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape.

// dendro-expect-file: low_cohesion
function celsius_to_fahrenheit($c) {
    return $c * 9 / 5 + 32;
}

function is_weekend($day) {
    return $day == 6 || $day == 7;
}

function canonical($text) {
    return to_lower(trim($text));
}

function label($n) {
    if ($n == 0) {
        return "zero";
    }
    return "other";
}

function checksum($xs, $n) {
    $total = 0;
    $i = 0;
    while ($i < $n) {
        $total += $xs[$i];
        $i = $i + 1;
    }
    return $total;
}

function byte_count($s) {
    return string_length($s) + 1;
}
