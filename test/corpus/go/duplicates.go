package corpus

// An exact clone pair: identical up to renamed identifiers, above the clone size
// floor.

// dendro-expect: duplicate
func totalPrice(items []int, tax int) int {
    subtotal := 0
    for i := 0; i < len(items); i++ {
        subtotal = subtotal + items[i]
    }
    grand := subtotal + subtotal*tax
    rounded := roundValue(grand)
    return rounded
}

// dendro-expect: duplicate
func finalAmount(rows []int, rate int) int {
    accum := 0
    for i := 0; i < len(rows); i++ {
        accum = accum + rows[i]
    }
    whole := accum + accum*rate
    snapped := roundValue(whole)
    return snapped
}
