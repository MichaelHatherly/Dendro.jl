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

# A ternary reached from another ternary's branch is a chain. One inside a call is not:
# the call is where the reader stops.
chained(v, hi, lo) = v >= hi ? :high : v >= lo ? :warn : :ok    # dendro-expect: nested_ternary
single(v, hi) = v >= hi ? :high : :ok
guarded(v, hi) = wrap(v >= hi ? :high : :ok)

# A parameter narrowed to a sized numeric type, positionally and as a keyword default.
scaled(x::Float64) = x                    # dendro-expect: concrete_numeric_parameter
counted(n::UInt32) = n                    # dendro-expect: concrete_numeric_parameter
weighted(x; w::Float64 = 0.5) = x * w     # dendro-expect: concrete_numeric_parameter

# The wider type dispatches the same, and `Int` is what a literal already is.
widened(x::Real, n::Integer) = x + n
indexed(i::Int) = i

# A return annotation asserts an inference result rather than narrowing dispatch, and a
# struct field is where a concrete type earns its keep. Neither is the rule's business.
asserted(x)::Float64 = x

struct Sized
    cut::Float64
end

# Splatting two operands to build a vector, against the concatenation that says it, and
# against a call that splats its arguments.
joined(a, b) = [a..., b...]    # dendro-expect: splat_concatenation
direct(a, b) = [a; b]
forwarded(a, b) = f(a..., b...)

# An inlining hint, either direction. A macro's name in a string is not a macro call.
@inline hinted(x) = x      # dendro-expect: manual_inline
@noinline blocked(x) = x   # dendro-expect: manual_inline
const HINTS = Set{String}(["@inline", "@noinline"])

# A `const` container built empty exists to be filled. One built with its entries is a
# lookup table, and one bound to an immutable value is an ordinary constant.
const CACHE = Dict{Symbol, Int}()    # dendro-expect: mutable_global
const TABLE = Dict{Symbol, Int}(:a => 1)
const BAND = (1, 2)

# A field access reaching through another field access. One step is how a record is read.
reaching(f) = f.index.functions    # dendro-expect: field_chain
shallow(f) = f.index
