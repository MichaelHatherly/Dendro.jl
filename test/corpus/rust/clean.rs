// Cohesive: each function calls the next, so the file is one connected component.

const LO: f64 = 0.0;
const HI: f64 = 1.0;

fn clampv(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo {
        return lo;
    }
    if x > hi {
        return hi;
    }
    return x;
}

fn normalize(x: f64) -> f64 {
    return clampv(x, LO, HI);
}

fn scale(x: f64, k: f64) -> f64 {
    return normalize(x) * k;
}

fn accumulate(xs: &[f64]) -> f64 {
    let mut total = 0.0;
    for x in xs {
        total += scale(*x, 2.0);
    }
    return total;
}
