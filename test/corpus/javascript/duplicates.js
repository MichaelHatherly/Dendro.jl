// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

// dendro-expect: duplicate
function totalPrice(items, tax) {
    let subtotal = 0;
    for (let i = 0; i < items.length; i++) {
        subtotal = subtotal + items[i];
    }
    let grand = subtotal + subtotal * tax;
    let rounded = roundValue(grand);
    return rounded;
}

// dendro-expect: duplicate
function finalAmount(rows, rate) {
    let accum = 0;
    for (let i = 0; i < rows.length; i++) {
        accum = accum + rows[i];
    }
    let whole = accum + accum * rate;
    let snapped = roundValue(whole);
    return snapped;
}
