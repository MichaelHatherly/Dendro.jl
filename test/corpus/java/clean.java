// Cohesive: each method calls the next, so the file is one connected component.

class CleanOps {
    static final double LO = 0.0;
    static final double HI = 1.0;

    double clampv(double x, double lo, double hi) {
        if (x < lo) {
            return lo;
        }
        if (x > hi) {
            return hi;
        }
        return x;
    }

    double normalize(double x) {
        return clampv(x, LO, HI);
    }

    double scale(double x, double k) {
        return normalize(x) * k;
    }

    double accumulate(double[] xs) {
        double total = 0.0;
        for (int i = 0; i < xs.length; i++) {
            total += scale(xs[i], 2);
        }
        return total;
    }
}
