# Fixtures for the Julia half of the pack Dendro ships.
#
# A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
# must not be, so the near-miss beside each rule is as much of the test as the match is.
#
# This file is read under two configurations: the pack alone, and the pack with the repo
# rules in `.dendro/patterns/` shadowing six of its names. Every shape below is one both
# spellings agree on, which is what lets one fixture pin both.

# dendro-expect: banner_comment
# ========================================

# --- A rule with a title in it is a heading and stays ---

function writes_the_test_out(c)
    if c    # dendro-expect: boolean_return
        return true
    else
        return false
    end
end

function returns_the_value(c, x)
    if c
        return true
    else
        return x
    end
end

function repeats_a_condition(x, y)
    if x > 0    # dendro-expect: unreachable_branch
        return 1
    elseif x > 0
        return 2
    end
    return 0
end

function tests_two_things(x, y)
    if x > 0
        return 1
    elseif y > 0
        return 2
    end
    return 0
end

function picks_the_larger(a, b)
    if a > b    # dendro-expect: manual_min_max
        return a
    else
        return b
    end
end

function picks_a_floor(a, b)
    if a > b
        return a
    else
        return 0
    end
end

function swallows(work)
    try    # dendro-expect: try_density
        return work()
    catch err    # dendro-expect: swallowed_error
        return nothing
    end
end

function handles_the_error(work, log)
    try    # dendro-expect: try_density
        return work()
    catch err
        log(err)
        return nothing
    end
end

function fails_two_ways(a, b, log)
    x = 0
    y = 0
    try    # dendro-expect: try_density
        x = a()
    catch err
        log(err)
    end
    try    # dendro-expect: try_density
        y = b()
    catch err
        log(err)
    end
    return x, y
end

function compares_a_flag(flag)
    if flag == true    # dendro-expect: boolean_equality
        return 1
    end
    if false === flag    # dendro-expect: boolean_equality
        return 2
    end
    if flag == 1
        return 1
    end
    if flag
        return 2
    end
    return 0
end

function counts_to_find_out(xs)
    if length(xs) == 0    # dendro-expect: empty_check
        return 1
    end
    if 0 == length(xs)    # dendro-expect: empty_check
        return 2
    end
    if length(xs) == 1
        return 1
    end
    if isempty(xs)
        return 2
    end
    return 0
end

function converts_and_back(x, s)
    a = parse(Int, string(x))    # dendro-expect: redundant_conversion
    b = string(parse(Int, s))    # dendro-expect: redundant_conversion
    c = parse(Int, s)
    d = string(x)
    return a, b, c, d
end

function asks_a_key_view(d, k)
    if k in keys(d)    # dendro-expect: redundant_keys
        return 1
    end
    if haskey(d, k)
        return 2
    end
    return 0
end

function materialises(itr)
    n = length(collect(itr))    # dendro-expect: redundant_collect
    for x in collect(itr)       # dendro-expect: redundant_collect
        n += 1
    end
    for y in itr
        n += 1
    end
    return n
end

function walks_positions(v)
    total = 0
    for i in 1:length(v)    # dendro-expect: length_index_range
        total += v[i]
    end
    for x in v
        total += x
    end
    return total
end

exactly_int(x) = typeof(x) == Int    # dendro-expect: type_equality
int_exactly(x) = Int != typeof(x)    # dendro-expect: type_equality
same_type(x, y) = typeof(x) == typeof(y)
is_int(x) = x isa Int

absent(x) = x == nothing      # dendro-expect: nothing_equality
present(x) = x != nothing     # dendro-expect: nothing_equality
reversed(x) = nothing == x    # dendro-expect: nothing_equality
identified(x) = x === nothing

function checks_every_argument(a, b, c)
    a isa Int || throw(ArgumentError("a"))       # dendro-expect: type_check_density
    b isa String || throw(ArgumentError("b"))    # dendro-expect: type_check_density
    c isa Vector || throw(ArgumentError("c"))    # dendro-expect: type_check_density
    return a, b, c
end

function asks_once(a)
    a isa Int && return a
    return 0
end

function guards_every_argument(a, b, c)
    a === nothing && return nothing    # dendro-expect: null_guard_density
    b === nothing && return            # dendro-expect: null_guard_density
    if c === nothing                   # dendro-expect: null_guard_density
        return nothing
    end
    return a, b, c
end

function substitutes_a_default(a, fallback)
    a === nothing && return fallback
    return a
end
