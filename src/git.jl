# Everything Dendro asks of a git repository, read through libgit2. The rest of the
# package calls the four functions here and never learns that git exists; nothing shells
# out, so `--base` and `--since` work where the `git` and `tar` binaries do not.
#
# The `LibGit2` stdlib owns repository and object lifetimes, since it already handles the
# finalizers and the library's own refcounted initialisation. Raw `ccall` covers only
# what the stdlib does not wrap, which is the hunk and line detail a diff scope needs.

"""
    git_toplevel(paths) -> String

The working directory of the repository containing the first of `paths`, found by
searching upward from that path's own directory. The repo root the diff scope, the
ratchet base, and the discovered `.dendro.toml` all resolve their relative paths
against. Throws a `LibGit2.GitError` when no repository contains the path, which is how
`repo_config_dir` tells a repo from a bare directory.
"""
function git_toplevel(paths::Union{AbstractString, AbstractVector{<:AbstractString}})
    ref = paths isa AbstractString ? paths : first(paths)
    dir = isdir(ref) ? ref : dirname(ref)
    # `GitRepoExt` searches parent directories, the `git rev-parse --show-toplevel`
    # behaviour; the plain `GitRepo` constructor demands the root itself.
    repo = LibGit2.GitRepoExt(dir)
    try
        # `git_repository_workdir` reports a trailing separator and the path as opened,
        # where `rev-parse` reported it resolved. `realpath` restores both, and every
        # caller keys relative paths against this, so the resolved form is the contract.
        return realpath(LibGit2.workdir(repo))
    finally
        close(repo)
    end
end

# libgit2's `git_diff_line`. The stdlib wraps the delta and file structs but not this one,
# so it is declared here and the layout has to match the C header exactly. A wrong field
# offset reads plausible line numbers rather than failing, which is what the equivalence
# test against the unified-diff parser exists to catch.
struct DiffLine
    origin::Cchar
    old_lineno::Cint
    new_lineno::Cint
    num_lines::Cint
    content_len::Csize_t
    content_offset::Int64
    content::Ptr{Cchar}
end

# The new-side line numbers `patch` adds. Lines are pulled out of each hunk rather than
# pushed through `git_diff_foreach`, so no callback back into Julia is needed.
function added_lines!(added::Vector{Int}, patch::Ptr{Cvoid})
    hunks = Int(ccall((:git_patch_num_hunks, LibGit2_jll.libgit2), Csize_t, (Ptr{Cvoid},), patch))
    for h in 0:(hunks - 1)
        lines = Int(
            ccall(
                (:git_patch_num_lines_in_hunk, LibGit2_jll.libgit2), Cint,
                (Ptr{Cvoid}, Csize_t), patch, h
            ),
        )
        for l in 0:(lines - 1)
            out = Ref{Ptr{DiffLine}}(C_NULL)
            ok = ccall(
                (:git_patch_get_line_in_hunk, LibGit2_jll.libgit2), Cint,
                (Ptr{Ptr{DiffLine}}, Ptr{Cvoid}, Csize_t, Csize_t), out, patch, h, l
            )
            ok == 0 || continue
            line = unsafe_load(out[])
            line.origin == Cchar('+') && push!(added, Int(line.new_lineno))
        end
    end
    return added
end

# Each delta's added lines, coalesced into ranges and keyed by the new-side path. A file
# with no added lines gets no entry, so a pure deletion and a binary change (which carries
# no hunks at all) both fall out rather than being special-cased.
function diff_ranges(diff::LibGit2.GitDiff)
    out = Dict{String, Vector{UnitRange{Int}}}()
    added = Int[]
    for i in 1:LibGit2.count(diff)
        patch = Ref{Ptr{Cvoid}}(C_NULL)
        ok = ccall(
            (:git_patch_from_diff, LibGit2_jll.libgit2), Cint,
            (Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, Csize_t), patch, diff, i - 1
        )
        ok == 0 || continue
        try
            empty!(added)
            added_lines!(added, patch[])
            isempty(added) || (out[unsafe_string(diff[i].new_file.path)] = coalesce_lines(added))
        finally
            ccall((:git_patch_free, LibGit2_jll.libgit2), Cvoid, (Ptr{Cvoid},), patch[])
        end
    end
    return out
end

"""
    changed_ranges(root, base) -> Dict{String,Vector{UnitRange{Int}}}

The line ranges each file added or changed between `base` and the working tree, keyed by
the path relative to `root`. The same question `git diff <base>` answers: the comparison
is against the working tree with the index folded in, not against the index alone, so an
uncommitted edit is in scope the way a review reads it.
"""
function changed_ranges(root::AbstractString, base)
    repo = LibGit2.GitRepoExt(root)
    return try
        tree = base_tree(repo, base, "base")
        diff = LibGit2.diff_tree(repo, tree)
        try
            return diff_ranges(diff)
        finally
            close(diff)
            close(tree)
        end
    finally
        close(repo)
    end
end

# The tree `ref` names, or a clean error naming the caller's own option. The ref is
# checked before anything is materialised, since a broken ref is misconfiguration and
# must not degrade into an empty base that reads as "everything is new".
function base_tree(repo::LibGit2.GitRepo, ref, keyword::AbstractString)
    commit = try
        LibGit2.GitCommit(repo, string(ref, "^{commit}"))
        # dendro-ignore: empty_catch_binding -- the only question is whether the ref resolved
    catch
        error("Dendro: `$keyword` ref not found: $ref")
    end
    try
        return LibGit2.GitTree(commit)
    finally
        close(commit)
    end
end

# Whether `path` is `rel` itself or sits beneath it. A `rel` of "." is the repo root,
# which every path is beneath.
under(path::AbstractString, rel::AbstractString) =
    rel == "." || path == rel || startswith(path, rel * "/")

# One tree entry written into the base corpus. A symlink's blob content is its target, so
# it is recreated as a link rather than as a file holding a path. A commit entry is a
# submodule, whose content lives in another repository and is not part of this corpus.
function write_entry(repo::LibGit2.GitRepo, entry::LibGit2.GitTreeEntry, dest::AbstractString)
    mode = LibGit2.filemode(entry)
    mode == Cint(LibGit2.Consts.FILEMODE_COMMIT) && return nothing
    blob = LibGit2.GitBlob(repo, LibGit2.entryid(entry))
    try
        mkpath(dirname(dest))
        bytes = LibGit2.rawcontent(blob)
        if mode == Cint(LibGit2.Consts.FILEMODE_LINK)
            symlink(String(bytes), dest)
        else
            write(dest, bytes)
            mode == Cint(LibGit2.Consts.FILEMODE_BLOB_EXECUTABLE) && chmod(dest, 0o755)
        end
    finally
        close(blob)
    end
    return nothing
end

# `tree` written into `dest`, restricted to the repo-relative paths in `rels`. Subtrees
# that cannot hold a wanted path are skipped rather than walked, so scoping a scan to one
# folder does not read every blob in the repository.
function checkout_tree(tree::LibGit2.GitTree, rels::Vector{String}, dest::AbstractString)
    repo = LibGit2.repository(tree)
    LibGit2.treewalk(tree) do dir, entry
        path = string(dir, LibGit2.filename(entry))
        if LibGit2.entrytype(entry) === LibGit2.GitTree
            # A wanted path may be this subtree, or may lie inside it.
            return any(r -> under(path, r) || under(r, path), rels) ? Cint(0) : Cint(1)
        end
        any(r -> under(path, r), rels) || return Cint(0)
        write_entry(repo, entry, joinpath(dest, path))
        return Cint(0)
    end
    return nothing
end

# `roots` as they stood at `ref`, materialised into a tempdir, passed to `f` as the
# tempdir root and the subset of `roots` that existed there. The tree is read straight
# from the object database, so no worktree is touched and no index is mutated.
#
# The corpus is scoped to `roots`, never the whole tree: a whole-tree base would give the
# base a different corpus from HEAD's, shifting the baseline, the clone corpus, and every
# graph built over it, which manufactures differences the change never made. Paths absent
# at `ref` are dropped, so `f` sees an empty vector rather than a phantom corpus.
#
# `f` is annotated `::F` to force a specialisation per callback. Julia does not specialise
# on a bare function argument, so without it every caller compiles to the same dynamic
# call and static analysis cannot see through the block. `keyword` is positional for the
# same reason: a keyword argument splits the method into a `kwcall` wrapper and a body,
# and every report against the body is then raised twice.
function with_base_corpus(f::F, roots::Vector{String}, ref, root::AbstractString, keyword::AbstractString = "base") where {F}
    repo = LibGit2.GitRepoExt(root)
    return try
        tree = base_tree(repo, ref, keyword)
        rels = [relpath(realpath(p), root) for p in roots]
        # `mktempdir` with a block would wrap `f` in a second closure that its own
        # signature types as `Any`, which costs every caller a call no static analysis can
        # see through. The `try` does the same cleanup one layer down.
        tmp = mktempdir()
        try
            checkout_tree(tree, rels, tmp)
            # macOS maps /tmp to /private/tmp; resolve the tempdir root so its relative
            # paths match HEAD's, or every path keyed against it misaligns.
            troot = realpath(tmp)
            tpaths = String[joinpath(troot, r) for r in rels if ispath(joinpath(troot, r))]
            return f(troot, tpaths)
        finally
            close(tree)
            rm(tmp; recursive = true, force = true)
        end
    finally
        close(repo)
    end
end
