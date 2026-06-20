// Cohesive: each function calls the next, so the file is one connected component.

static const double LO = 0.0;
static const double HI = 1.0;

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

double accumulate(const std::vector<double> &xs) {
    double total = 0.0;
    for (auto x : xs) {
        total += scale(x, 2);
    }
    return total;
}
