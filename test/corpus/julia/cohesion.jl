# A grab-bag of unrelated helpers: six functions that share no file-local binding
# and never call one another, so the file splits into six independent concerns and
# trips the cohesion band. The marker is file-scoped: cohesion is a per-file metric.

# dendro-expect-file: low_cohesion
function celsius_to_fahrenheit(c)
    return c * 9 / 5 + 32
end

function slugify(text)
    return lowercase(replace(text, " " => "-"))
end

function clamp01(x)
    return max(0.0, min(1.0, x))
end

function byte_count(s)
    return ncodeunits(s)
end

function is_weekend(day)
    return day == 6 || day == 7
end

function pad_left(s, n)
    return repeat(" ", n) * s
end
