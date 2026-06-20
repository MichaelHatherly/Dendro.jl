# An exact clone pair: identical up to renamed identifiers, above the clone size
# floor, reported as a :duplicate cluster.

# dendro-expect: duplicate
def total_price(items, tax):
    subtotal = 0
    for item in items:
        subtotal = subtotal + item
    grand = subtotal + subtotal * tax
    rounded = round(grand)
    return rounded


# dendro-expect: duplicate
def final_amount(rows, rate):
    accum = 0
    for row in rows:
        accum = accum + row
    whole = accum + accum * rate
    snapped = round(whole)
    return snapped
