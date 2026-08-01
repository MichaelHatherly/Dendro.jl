#! format: off
#
# Fixtures for Dendro's own pattern rules. A line marked `dendro-expect` must be reported
# by that rule, and an unmarked line must not: a rule matching everything would pass a
# fixture that only checked for a match.
#
# Formatting is off for the whole file because the spelling is the assertion: `bt!==nothing`
# below tests a rule against how the grammar tokenises it, and a formatter adding the spaces
# would silently retire the case.
#
# Most of these rules are guards, so this file is the only place they ever fire. That makes
# the negative cases the load-bearing half: a guard nobody exercises against code it must
# stay quiet on is a guard nobody has tested.

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

# A bound exception discarded anyway, in each of the three shapes that discard it. The
# marker sits on the `catch`, which is the node the rule reports.
function discards_bare(x)
    try
        risky(x)
    catch err    # dendro-expect: swallowed_error
        return
    end
end

function discards_nothing(x)
    try
        risky(x)
    catch err    # dendro-expect: swallowed_error
        return nothing
    end
end

function discards_bare_value(x)
    try
        risky(x)
    catch err    # dendro-expect: swallowed_error
        nothing
    end
end

# Handling is not discarding. A body that logs, rethrows, or returns something derived from
# the error has done something with it.
function logs(x)
    try
        risky(x)
    catch err
        @warn "failed" err
    end
end

function rethrows(x)
    try
        risky(x)
    catch err
        rethrow()
    end
end

function converts(x)
    try
        risky(x)
    catch err
        return err
    end
end

# `NaN` compares unequal to everything, so every one of these branches is dead.
is_missing_value(x) = x == NaN       # dendro-expect: nan_comparison
is_present(x) = x !== NaN            # dendro-expect: nan_comparison
nan_reversed(x) = NaN == x           # dendro-expect: nan_comparison
is_missing_properly(x) = isnan(x)

# Identity against `nothing`, not equality. `!==` and `===` are the correct spellings and
# must stay quiet.
absent(x) = x == nothing             # dendro-expect: nothing_equality
present(x) = x != nothing            # dendro-expect: nothing_equality
reversed(x) = nothing == x           # dendro-expect: nothing_equality
absent_ok(x) = x === nothing
present_ok(x) = x !== nothing
absent_best(x) = isnothing(x)
# Written without spaces the grammar reads `bt!` and `==`, so the correct spelling would
# report as the wrong one.
unspaced_ok(bt) = bt!==nothing

# An exact-type test where a subtype question was meant, in both operand orders.
exactly_int(x) = typeof(x) == Int    # dendro-expect: type_equality
int_exactly(x) = Int != typeof(x)    # dendro-expect: type_equality
an_int(x) = x isa Integer
# Comparing two types that both arrived as values is a question `==` answers correctly.
same_type(x, y) = typeof(x) === typeof(y)
matches_stored(stored, x) = stored == typeof(x)
from_call(io, x) = get(io, :typeinfo, Any) == typeof(x)

# Reaching into a `match` result that may be `nothing`.
first_capture(re, s) = match(re, s).captures    # dendro-expect: unchecked_match
first_group(re, s) = match(re, s)[1]            # dendro-expect: unchecked_match

function checked(re, s)
    m = match(re, s)
    return m === nothing ? nothing : m.captures
end

# A loop range that writes down where the container starts.
function summed(v)
    total = 0
    for i in 1:length(v)    # dendro-expect: length_index_range
        total += v[i]
    end
    return total
end

function summed_ok(v)
    total = 0
    for i in eachindex(v)
        total += v[i]
    end
    return total
end

function summed_also_ok(v, n)
    total = 0
    for i in 1:n
        total += v[i]
    end
    return total
end

# `collect` where the surrounding call would have iterated the lazy sequence.
function counted(itr)
    n = length(collect(itr))    # dendro-expect: redundant_collect
    for x in collect(itr)       # dendro-expect: redundant_collect
        use(x)
    end
    return n
end

function counted_ok(itr)
    n = count(_ -> true, itr)
    materialised = collect(itr)
    return n, materialised
end

# A container with no element type holds `Any`.
empty_vector() = []                 # dendro-expect: untyped_container
empty_dict() = Dict()               # dendro-expect: untyped_container
empty_set() = Set()                 # dendro-expect: untyped_container
typed_vector() = Int[]
typed_dict() = Dict{String, Int}()
typed_set() = Set{Symbol}()
indexing(v, i) = v[i]
deref(r) = r[]
# `BitSet` takes no parameters: its elements are always `Int`.
empty_bitset() = BitSet()

# `eval` inside a function body, as a call and as a macro. At module scope it is ordinary
# metaprogramming and must stay quiet.
function defines(name)
    return eval(:(const $name = 1))    # dendro-expect: eval_in_function
end

function defines_by_macro(name)
    @eval const $name = 1              # dendro-expect: eval_in_function
    return name
end

@eval const MODULE_SCOPE = 1

# A function reaching for a global.
function bump()
    global counter    # dendro-expect: global_in_function
    counter += 1
    return counter
end

const COUNTER = Ref(0)
bump_ok() = COUNTER[] += 1

# Abstractly typed struct fields, against the parametric form that keeps them concrete.
struct Handler
    fn::Function        # dendro-expect: abstract_field
    label::Any          # dendro-expect: abstract_field
    entries::Dict       # dendro-expect: abstract_field
end

struct Concrete{F}
    fn::F
    label::String
    entries::Dict{String, Int}
end

# Splatting two operands to build a vector, against the concatenation that says it, and
# against a call that splats its arguments.
joined(a, b) = [a..., b...]    # dendro-expect: splat_concatenation
typed_join(a, b) = Symbol[a..., b...]    # dendro-expect: splat_concatenation
direct(a, b) = [a; b]
forwarded(a, b) = f(a..., b...)
# Spreading dimensions into an index builds no vector, and parses as the same node the
# typed literal above does.
sliced(out, before, i, after) = out[before..., i, after...]

# An `elseif` repeating a condition an earlier branch already took. The marker sits on the
# `if`, which is the node the rule reports. Literals stay at 0, 1, or 2 throughout: any
# other number would make these fixtures fire `magic_number` as well.
function repeats_the_if(x)
    if x > 0    # dendro-expect: unreachable_branch
        return :pos
    elseif x > 0
        return :never
    end
end

function repeats_an_elseif(x)
    if x > 2    # dendro-expect: unreachable_branch
        return :big
    elseif x > 0
        return :pos
    elseif x > 0
        return :never
    end
end

# The same condition respelled. The comparison reads trees rather than text, so the spacing
# does not hide it, which is the case `#eq?` would have missed.
function respelled(x)
    if x > 0    # dendro-expect: unreachable_branch
        return :pos
    elseif x>0
        return :never
    end
end

# Distinct conditions are an ordinary chain. A second test of the same variable is only
# unreachable when it is the same test, so a renamed operand must stay quiet.
function distinct(x)
    if x > 2
        return :big
    elseif x > 0
        return :pos
    else
        return :neg
    end
end

function renamed(x, y)
    if x > 0
        return :x
    elseif y > 0
        return :y
    end
end

# Introspection macros left in source. `@info` and `@debug` are logging and stay quiet.
inspect(x) = @show x                     # dendro-expect: debug_output
warntype(f, x) = @code_warntype f(x)     # dendro-expect: debug_output
lowered(f, x) = @code_lowered f(x)       # dendro-expect: debug_output
open_it(f, x) = @edit f(x)               # dendro-expect: debug_output
logs_it(x) = @info "value" x
debugs_it(x) = @debug "value" x
times_it(x) = @time work(x)

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
