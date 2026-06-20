// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape,
// so none reads as a clone of another.

// dendro-expect-file: low_cohesion
double celsius_to_fahrenheit(double c) {
    return c * 9 / 5 + 32;
}

int is_weekend(int day) {
    return day == 6 || day == 7;
}

char *canonical(char *text) {
    return to_lower(trim(text));
}

const char *label(int n) {
    if (n == 0) {
        return "zero";
    }
    return "other";
}

int checksum(const int *xs, int n) {
    int total = 0;
    int i = 0;
    while (i < n) {
        total += xs[i];
        i = i + 1;
    }
    return total;
}

int byte_count(const char *s) {
    return string_length(s) + 1;
}
