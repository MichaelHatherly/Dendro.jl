// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

// dendro-expect: duplicate
int total_price(const int *items, int n, int tax) {
    int subtotal = 0;
    for (int i = 0; i < n; i++) {
        subtotal = subtotal + items[i];
    }
    int grand = subtotal + subtotal * tax;
    int rounded = round_value(grand);
    return rounded;
}

// dendro-expect: duplicate
int final_amount(const int *rows, int n, int rate) {
    int accum = 0;
    for (int i = 0; i < n; i++) {
        accum = accum + rows[i];
    }
    int whole = accum + accum * rate;
    int snapped = round_value(whole);
    return snapped;
}
