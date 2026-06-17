# Path ignoring. Vendored and generated source should not be measured at all: it
# is not the author's code, and a large vendored tree skews the percentile baseline
# every scanned file feeds. The `ignore` patterns passed to `analyze` drop matching
# files at collection time, before parsing, so they leave both the findings and the
# baseline. Patterns follow gitignore rules, matched against the path relative to the
# scanned root.

struct IgnorePattern
    negated::Bool
    dir_only::Bool
    re::Regex
end

# Translate one gitignore glob to an anchored regex. A leading `/`, or any `/` before
# the final character, anchors the pattern to the root; otherwise it matches at any
# depth. `*` and `?` stop at a separator, `**` spans them.
function glob_to_regex(pat::AbstractString)
    anchored = false
    if startswith(pat, '/')
        anchored = true
        pat = pat[nextind(pat, firstindex(pat)):end]
    elseif occursin('/', pat)
        anchored = true
    end
    chars = collect(pat)
    out = IOBuffer()
    i = 1
    n = length(chars)
    while i <= n
        c = chars[i]
        if c == '*' && i < n && chars[i + 1] == '*'
            if i + 2 <= n && chars[i + 2] == '/'
                print(out, "(?:.*/)?")   # `**/` spans zero or more directories
                i += 3
            else
                print(out, ".*")
                i += 2
            end
        elseif c == '*'
            print(out, "[^/]*")
            i += 1
        elseif c == '?'
            print(out, "[^/]")
            i += 1
        elseif c == '/'
            print(out, '/')
            i += 1
        else
            c in raw".()[]{}+^$|\\" && print(out, '\\')
            print(out, c)
            i += 1
        end
    end
    prefix = anchored ? "^" : "(?:^|.*/)"
    return Regex(string(prefix, String(take!(out)), "\$"))
end

"""
    compile_ignores(patterns) -> Vector{IgnorePattern}

Compile gitignore-style pattern strings once for repeated matching. A leading `!`
negates (re-includes), a trailing `/` matches directories only. Blank patterns are
dropped.
"""
function compile_ignores(patterns)
    out = IgnorePattern[]
    for raw in patterns
        pat = String(raw)
        negated = startswith(pat, '!')
        negated && (pat = pat[nextind(pat, firstindex(pat)):end])
        dir_only = endswith(pat, '/')
        dir_only && (pat = chop(pat))
        isempty(pat) && continue
        push!(out, IgnorePattern(negated, dir_only, glob_to_regex(pat)))
    end
    return out
end

"""
    is_ignored(patterns, path, isdir) -> Bool

Whether `path` (relative to the scanned root, `/`-separated) is ignored by the
compiled `patterns`. The last matching pattern decides, so a later negation
re-includes an earlier match. Directory-only patterns match only when `isdir`.
"""
function is_ignored(patterns, path::AbstractString, isdir::Bool)
    path = replace(path, '\\' => '/')
    ignored = false
    for p in patterns
        p.dir_only && !isdir && continue
        occursin(p.re, path) && (ignored = !p.negated)
    end
    return ignored
end
