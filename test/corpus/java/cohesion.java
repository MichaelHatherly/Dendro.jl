// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape.

class CohesionOps {
    // dendro-expect-file: low_cohesion
    double celsiusToFahrenheit(double c) {
        return c * 9 / 5 + 32;
    }

    boolean isWeekend(int day) {
        return day == 6 || day == 7;
    }

    String canonical(String text) {
        return toLower(trim(text));
    }

    String label(int n) {
        if (n == 0) {
            return "zero";
        }
        return "other";
    }

    int checksum(int[] xs, int n) {
        int total = 0;
        int i = 0;
        while (i < n) {
            total += xs[i];
            i = i + 1;
        }
        return total;
    }

    int byteCount(String s) {
        return stringLength(s) + 1;
    }
}
