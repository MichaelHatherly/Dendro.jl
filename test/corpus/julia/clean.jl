# A running-statistics accumulator. The functions form one connected concern:
# each works on the same state shape and they call one another, so the file reads
# as a single cohesive unit and trips no metric. This is the true-negative case.

const EPSILON = 1.0e-9

new_stats() = (count = 0, mean = 0.0, m2 = 0.0)

function push_value(stats, x)
    count = stats.count + 1
    delta = x - stats.mean
    mean = stats.mean + delta / count
    m2 = stats.m2 + delta * (x - mean)
    return (count = count, mean = mean, m2 = m2)
end

function variance(stats)
    if stats.count < 2
        return 0.0
    end
    return stats.m2 / (stats.count - 1)
end

function stddev(stats)
    v = variance(stats)
    return sqrt(v + EPSILON)
end

function summarize(values)
    stats = new_stats()
    for v in values
        stats = push_value(stats, v)
    end
    return (mean = stats.mean, sd = stddev(stats))
end
