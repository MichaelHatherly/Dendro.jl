// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

// dendro-expect: duplicate
fn total_price(items: &[i32], tax: i32) -> i32 {
    let mut subtotal = 0;
    for i in 0..items.len() {
        subtotal = subtotal + items[i];
    }
    let grand = subtotal + subtotal * tax;
    let rounded = round_value(grand);
    return rounded;
}

// dendro-expect: duplicate
fn final_amount(rows: &[i32], rate: i32) -> i32 {
    let mut accum = 0;
    for i in 0..rows.len() {
        accum = accum + rows[i];
    }
    let whole = accum + accum * rate;
    let snapped = round_value(whole);
    return snapped;
}
