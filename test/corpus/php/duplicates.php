<?php

// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

// dendro-expect: duplicate
function total_price($items, $tax) {
    $subtotal = 0;
    for ($i = 0; $i < count($items); $i++) {
        $subtotal = $subtotal + $items[$i];
    }
    $grand = $subtotal + $subtotal * $tax;
    $rounded = round_value($grand);
    return $rounded;
}

// dendro-expect: duplicate
function final_amount($rows, $rate) {
    $accum = 0;
    for ($i = 0; $i < count($rows); $i++) {
        $accum = $accum + $rows[$i];
    }
    $whole = $accum + $accum * $rate;
    $snapped = round_value($whole);
    return $snapped;
}
