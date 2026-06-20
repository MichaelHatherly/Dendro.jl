#!/usr/bin/env bash
# Cohesive: each function calls the next, so the file is one connected component.

clampv() {
  if [ "$1" -lt "$2" ]; then
    echo "$2"
    return
  fi
  if [ "$1" -gt "$3" ]; then
    echo "$3"
    return
  fi
  echo "$1"
}

normalize() {
  clampv "$1" 0 1
}

scale() {
  local n
  n=$(normalize "$1")
  echo $((n * $2))
}

accumulate() {
  local total=0
  for x in $1; do
    total=$((total + $(scale "$x" 2)))
  done
  echo "$total"
}
