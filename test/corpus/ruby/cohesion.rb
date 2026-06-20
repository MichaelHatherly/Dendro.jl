# Six unrelated helpers that share no file-local binding and never call one another,
# so the file splits into six independent concerns. Each has a distinct body shape.

# dendro-expect-file: low_cohesion
def celsius_to_fahrenheit(c)
  c * 9 / 5 + 32
end

def is_weekend(day)
  day == 6 || day == 7
end

def canonical(text)
  to_lower(trim(text))
end

def label(n)
  if n == 0
    return "zero"
  end
  "other"
end

def checksum(xs, n)
  total = 0
  i = 0
  while i < n
    total += xs[i]
    i = i + 1
  end
  total
end

def byte_count(s)
  string_length(s) + 1
end
