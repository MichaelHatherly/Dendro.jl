# An exact clone pair: identical up to renamed identifiers, above the clone size
# floor.

# dendro-expect: duplicate
def total_price(items, tax)
  subtotal = 0
  i = 0
  while i < items.length
    subtotal = subtotal + items[i]
    i = i + 1
  end
  grand = subtotal + subtotal * tax
  rounded = round_value(grand)
  rounded
end

# dendro-expect: duplicate
def final_amount(rows, rate)
  accum = 0
  i = 0
  while i < rows.length
    accum = accum + rows[i]
    i = i + 1
  end
  whole = accum + accum * rate
  snapped = round_value(whole)
  snapped
end
