// Six unrelated helpers that share no file-local binding and never call one another,
// so the file splits into six independent concerns. Each has a distinct body shape.

// dendro-expect-file: low_cohesion
function celsiusToFahrenheit(c: number): number {
    return c * 9 / 5 + 32;
}

function isWeekend(day: number): boolean {
    return day === 6 || day === 7;
}

function canonical(text: string): string {
    return toLower(trim(text));
}

function label(n: number): string {
    if (n === 0) {
        return "zero";
    }
    return "other";
}

function checksum(xs: number[], n: number): number {
    let total = 0;
    let i = 0;
    while (i < n) {
        total += xs[i];
        i = i + 1;
    }
    return total;
}

function byteCount(s: string): number {
    return stringLength(s) + 1;
}
