# Fixtures for Dendro's own pattern rules. A line marked `dendro-expect` must be reported
# by that rule, and an unmarked line must not: a rule matching everything would pass a
# fixture that only checked for a match.

function bare_handler(x)
    try
        risky(x)
    catch    # dendro-expect: empty_catch_binding
        return nothing
    end
end

function commented_handler(x)
    try
        risky(x)
    catch    # dendro-expect: empty_catch_binding -- a comment must not defeat the rule
        return nothing
    end
end

function bound_handler(x)
    try
        risky(x)
    catch err
        return err
    end
end

# A fixture pins what the query matches, not what the score comes to: the band and the
# percentile are Dendro's and are tested elsewhere. So a scalar rule marks the line its
# occurrences sit on, exactly as a flag rule does.
#
# Four counted literals here: 7, 13, 42, 99. The 0, 1, and 2 are excluded, so a function
# doing ordinary index arithmetic does not accumulate a score.
function numeric(x)
    return x + 0 + 1 + 2 + 7 + 13 + 42 + 99    # dendro-expect: magic_number
end

function tame(x)
    return x + 0 + 1 + 2
end

# A literal bound to a name is not magic. None of these lines is marked, so the rule
# firing on any of them is a false positive the check reports.
function named(x)
    threshold = 7
    const LIMIT = 13
    scaled = 0.5
    return x * threshold + LIMIT + scaled
end

# A keyword default names its number too.
padded(x, width = 80) = x * width

# But a literal inside a larger expression is still unnamed: the assignment names the
# result, not the parts.
function compound(x)
    span = 7 + 13    # dendro-expect: magic_number
    return x + span
end
