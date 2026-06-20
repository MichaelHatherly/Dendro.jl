# Six unrelated helpers that share no file-local binding and never call one another,
# so the file splits into six independent concerns and trips the cohesion band.

# dendro-expect-file: low_cohesion
def celsius_to_fahrenheit(c):
    return c * 9 / 5 + 32


def slugify(text):
    return text.lower().replace(" ", "-")


def clamp01(x):
    return max(0.0, min(1.0, x))


def byte_count(s):
    return len(s.encode("utf-8"))


def is_weekend(day):
    return day == 6 or day == 7


def pad_left(s, n):
    return " " * n + s
