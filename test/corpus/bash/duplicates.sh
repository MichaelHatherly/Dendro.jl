#!/usr/bin/env bash
# An exact clone pair: identical up to renamed identifiers.

# dendro-expect: duplicate
total_price() {
  local subtotal=0
  for item in $1; do
    subtotal=$((subtotal + item))
  done
  local grand=$((subtotal + subtotal * $2))
  local rounded=$((grand / 1))
  echo "$rounded"
}

# dendro-expect: duplicate
final_amount() {
  local accum=0
  for row in $1; do
    accum=$((accum + row))
  done
  local whole=$((accum + accum * $2))
  local snapped=$((whole / 1))
  echo "$snapped"
}
