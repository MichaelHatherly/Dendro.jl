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

"""
    empty_body(node, profile) -> Bool

True when the function `node` has no body, or a body with no statements.
"""
function empty_body(node::TreeSitter.Node, profile::LanguageProfile)
    body = first_child_of(node, profile.body_types)
    body === nothing && return true
    return TreeSitter.count_named_nodes(body) == 0
end

"""
    empty_catches(tree, profile) -> Vector{TreeSitter.Node}

Exception-handling clauses with an empty or absent body, which swallow errors.
"""
function empty_catches(tree, profile::LanguageProfile)
    out = TreeSitter.Node[]
    TreeSitter.traverse(tree) do n, enter
        if enter && TreeSitter.node_type(n) in profile.catch_types
            body = first_child_of(n, profile.body_types)
            if body === nothing || TreeSitter.count_named_nodes(body) == 0
                push!(out, n)
            end
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
