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
