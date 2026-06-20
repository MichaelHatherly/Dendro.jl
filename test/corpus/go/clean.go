package corpus

// Cohesive: each function calls the next, so the file is one connected component.

const LO = 0.0
const HI = 1.0

func clampv(x float64, lo float64, hi float64) float64 {
    if x < lo {
        return lo
    }
    if x > hi {
        return hi
    }
    return x
}

func normalize(x float64) float64 {
    return clampv(x, LO, HI)
}

func scale(x float64, k float64) float64 {
    return normalize(x) * k
}

func accumulate(xs []float64) float64 {
    total := 0.0
    for i := 0; i < len(xs); i++ {
        total += scale(xs[i], 2)
    }
    return total
}
