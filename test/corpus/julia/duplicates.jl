# An exact clone pair: two functions identical up to renamed identifiers, each well
# above the clone size floor, reported as a `:duplicate` cluster.

# dendro-expect: duplicate
function total_price(items, tax)
    subtotal = 0
    for item in items
        subtotal = subtotal + item
    end
    grand = subtotal + subtotal * tax
    rounded = round(grand)
    return rounded
end

# dendro-expect: duplicate
function final_amount(rows, rate)
    accum = 0
    for row in rows
        accum = accum + row
    end
    whole = accum + accum * rate
    snapped = round(whole)
    return snapped
end
