// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape,
// so none reads as a clone of another.

// dendro-expect-file: low_cohesion
fn celsius_to_fahrenheit(c: f64) -> f64 {
    return c * 9.0 / 5.0 + 32.0;
}

fn is_weekend(day: i32) -> bool {
    return day == 6 || day == 7;
}

fn canonical(text: &str) -> String {
    return to_lower(trim(text));
}

fn label(n: i32) -> &'static str {
    if n == 0 {
        return "zero";
    }
    return "other";
}

fn checksum(xs: &[i32], n: i32) -> i32 {
    let mut total = 0;
    let mut i = 0;
    while i < n {
        total += xs[i as usize];
        i = i + 1;
    }
    return total;
}

fn byte_count(s: &str) -> usize {
    return string_length(s) + 1;
}
