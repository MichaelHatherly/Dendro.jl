# Cohesive: each method calls the next, so the file is one connected component.

LO = 0.0
HI = 1.0

def clampv(x, lo, hi)
  if x < lo
    return lo
  end
  if x > hi
    return hi
  end
  x
end

def normalize(x)
  clampv(x, LO, HI)
end

def scale(x, k)
  normalize(x) * k
end

def accumulate(xs)
  total = 0.0
  xs.each do |x|
    total += scale(x, 2)
  end
  total
end
