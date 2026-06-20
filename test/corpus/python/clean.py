# Cohesive: each function calls the next, so the file is one connected component
# and trips no metric. The true-negative case.

LO = 0.0
HI = 1.0


def clampv(x, lo, hi):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x


def normalize(x):
    return clampv(x, LO, HI)


def scale(x, k):
    return normalize(x) * k


def accumulate(xs):
    total = 0.0
    for x in xs:
        total += scale(x, 2)
    return total
