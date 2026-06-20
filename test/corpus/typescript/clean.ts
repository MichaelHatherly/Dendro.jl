// Cohesive: each function calls the next, so the file is one connected component.

const LO: number = 0.0;
const HI: number = 1.0;

function clampv(x: number, lo: number, hi: number): number {
    if (x < lo) {
        return lo;
    }
    if (x > hi) {
        return hi;
    }
    return x;
}

function normalize(x: number): number {
    return clampv(x, LO, HI);
}

function scale(x: number, k: number): number {
    return normalize(x) * k;
}

function accumulate(xs: number[]): number {
    let total = 0.0;
    for (let i = 0; i < xs.length; i++) {
        total += scale(xs[i], 2);
    }
    return total;
}
