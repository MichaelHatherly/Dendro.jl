// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

class DuplicateOps {
    // dendro-expect: duplicate
    int totalPrice(int[] items, int tax) {
        int subtotal = 0;
        for (int i = 0; i < items.length; i++) {
            subtotal = subtotal + items[i];
        }
        int grand = subtotal + subtotal * tax;
        int rounded = roundValue(grand);
        return rounded;
    }

    // dendro-expect: duplicate
    int finalAmount(int[] rows, int rate) {
        int accum = 0;
        for (int i = 0; i < rows.length; i++) {
            accum = accum + rows[i];
        }
        int whole = accum + accum * rate;
        int snapped = roundValue(whole);
        return snapped;
    }
}
