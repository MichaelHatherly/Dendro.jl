# Flag metrics: presence is the finding, no distribution. These target failure
# modes common in generated code, swallowed errors and unfinished stubs.

const STUB_PATTERN = r"\b(?:TODO|FIXME|XXX|HACK)\b"i

# First direct child of `node` whose type is in `types`, or `nothing`.
function first_child_of(node::TreeSitter.Node, types::Set{String})
    for c in TreeSitter.children(node)
        TreeSitter.node_type(c) in types && return c
    end
    return nothing
end

# Named children of a body that do real work, ignoring no-op statements like
# `pass`. A body is effectively empty when this count is zero.
function nontrivial_count(body::TreeSitter.Node, profile::LanguageProfile)
    n = 0
    for c in TreeSitter.children(body)
        TreeSitter.is_named(c) || continue
        TreeSitter.node_type(c) in profile.trivial_body_types || (n += 1)
    end
    return n
end

# True when a body node is missing or does no real work.
function empty_block(body, profile::LanguageProfile)
    body === nothing && return true
    return nontrivial_count(body, profile) == 0
end

"""
    empty_body(node, profile) -> Bool

True when the function `node` has no body, or a body that does no real work.
"""
empty_body(node::TreeSitter.Node, profile::LanguageProfile) =
    empty_block(first_child_of(node, profile.body_types), profile)

"""
    empty_bodies(tree, profile) -> Vector{TreeSitter.Node}

Function nodes with no body, or a body that does no real work.
"""
empty_bodies(tree, profile::LanguageProfile) =
    [u.node for u in functions(tree, profile) if empty_body(u.node, profile)]

"""
    empty_catches(tree, profile) -> Vector{TreeSitter.Node}

Exception-handling clauses with an empty or absent body, which swallow errors.
"""
function empty_catches(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.catch_types
            empty_block(first_child_of(n, profile.body_types), profile) && push!(out, n)
        end
        nothing
    end
    return out
end

"""
    stub_markers(tree, profile, source) -> Vector{TreeSitter.Node}

Comment nodes carrying a stub marker (`TODO`, `FIXME`, `XXX`, `HACK`).
"""
function stub_markers(tree, profile::LanguageProfile, source::AbstractString)
    out = TreeSitter.Node[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.comment_types
            occursin(STUB_PATTERN, TreeSitter.slice(source, n)) && push!(out, n)
        end
        nothing
    end
    return out
end
