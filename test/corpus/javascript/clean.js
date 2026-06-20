// Cohesive: each function calls the next, so the file is one connected component.

const LO = 0.0;
const HI = 1.0;

function clampv(x, lo, hi) {
    if (x < lo) {
        return lo;
    }
    if (x > hi) {
        return hi;
    }
    return x;
}

function normalize(x) {
    return clampv(x, LO, HI);
}

function scale(x, k) {
    return normalize(x) * k;
}

function accumulate(xs) {
    let total = 0.0;
    for (let i = 0; i < xs.length; i++) {
        total += scale(xs[i], 2);
    }
    return total;
}
