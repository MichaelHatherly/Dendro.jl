# Redundant-logic flags: a self comparison, an if whose arms are identical, and an
# empty body. Three functions, no shared binding, so the file stays under the
# cohesion band.

const FLOOR = 0

function is_valid(x)
    # dendro-expect: identical_operands
    return x == x
end

function pick(flag, a, b)
    # dendro-expect: duplicate_branches
    if flag > FLOOR
        return a + b
    else
        return a + b
    end
end

# dendro-expect: empty_body
function reset!(state)
end
