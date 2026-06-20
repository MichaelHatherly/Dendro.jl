package corpus

// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape,
// so none reads as a clone of another.

// dendro-expect-file: low_cohesion
func celsiusToFahrenheit(c float64) float64 {
    return c*9/5 + 32
}

func isWeekend(day int) bool {
    return day == 6 || day == 7
}

func canonical(text string) string {
    return toLower(trim(text))
}

func label(n int) string {
    if n == 0 {
        return "zero"
    }
    return "other"
}

func checksum(xs []int, n int) int {
    total := 0
    i := 0
    for i < n {
        total += xs[i]
        i = i + 1
    }
    return total
}

func byteCount(s string) int {
    return stringLength(s) + 1
}
