# The quality gate. `analyze` answers triage, "where to look", and wants percentile
# and rank, so its result is never empty. A gate wants pass/fail: satisfiable and
# stable. `errors` is that view, the error-severity findings, optionally narrowed to
# those a change introduced since a base ref.

# The error floor: findings at the `:high` absolute band. High-band scalars and every
# flag (flags are always `:high`). Percentile-only findings carry `:ok`/`:warn` and
# fall out, so the floor is satisfiable, never the worst-N% that always exists.
high_floor(findings) = Findings(filter(f -> f.absolute === :high, findings))

"""
    errors(paths; rules=BUILTIN_RULES, ignore=String[], language=nothing) -> Findings

The error-severity findings over `paths`: the deterministic floor, every finding at
the `:high` absolute band (high-band scalars and all flags), with inline
`dendro-ignore` directives applied first so a suppressed finding lifts the gate.

This is the gate companion to [`analyze`](@ref). `analyze` ranks by corpus percentile
for triage and so is never empty; `errors` reads only the fixed bands, so it is
satisfiable and stable, suitable for a CI gate. Assert `isempty(errors(path))` in a
test and every package's existing `Pkg.test()` gates on Dendro for free.

`rules`, `ignore`, and `language` pass through to [`analyze`](@ref).
"""
function errors(
        paths::Union{AbstractString, AbstractVector{<:AbstractString}};
        rules = BUILTIN_RULES, ignore = String[], language = nothing
    )
    return high_floor(active(analyze(paths; rules, ignore, language)))
end
