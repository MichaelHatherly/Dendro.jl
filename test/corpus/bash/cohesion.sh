#!/usr/bin/env bash
# Six unrelated helpers that share no file-local binding and never call one another,
# so the file splits into six independent concerns.

# dendro-expect-file: low_cohesion
celsius_to_fahrenheit() {
  echo $(( $1 * 9 / 5 + 32 ))
}

is_weekend() {
  if [ "$1" -eq 6 ] || [ "$1" -eq 7 ]; then
    echo 1
  else
    echo 0
  fi
}

canonical() {
  to_lower "$(trim "$1")"
}

label() {
  if [ "$1" -eq 0 ]; then
    echo "zero"
    return
  fi
  echo "other"
}

checksum() {
  local total=0
  for v in $1; do
    total=$((total + v))
  done
  echo "$total"
}

byte_count() {
  echo $(( ${#1} + 1 ))
}
