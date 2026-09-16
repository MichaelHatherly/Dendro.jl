# How many things a directory holds. The other directory rules all read coupling:
# `:incoherent_package` asks whether a directory's contents belong elsewhere and
# `:divisible_package` whether they want subdividing where they are. A directory whose
# coupling is perfect by both readings can still hold ninety files, and then there is
# nothing wrong with where the code sits and everything wrong with finding any of it. That
# is the observation this makes, and it is the one `cluster_divisible_packages` names as its
# own blind spot: no reading of the graph finds it.
#
# The node set is the one `:divisible_package` reads, a directory's direct children, a child
# file as one node and a child subdirectory as one node. So the two rules are a matched
# pair. This one says a directory has too many children; that one says how they group.
#
# The count is the score and nothing else is. The lines a directory holds and how unevenly
# they are spread across its children both describe it, and neither says whether a reader
# can find anything, so they ride in the label where a reader can weigh them.
#
# Syntactic and shallow like the rest of the layout rules. The directory comes from the
# path, and the children come from walking those paths with `dirname`.

# Absolute band on a directory's direct child count.
#
# Measured, where most bands are a standard drawn from published guidance. Nobody publishes
# a limit on how wide a directory should be. The one number in circulation is Valknut's
# Gaussian about seven, and that is a scoring curve over working memory rather than a limit
# anybody holds a repository to. So the corpus is what is left, the position
# `comment_density` set the precedent for, and a measured band is also why this rule ships
# off by default: it says where codebases sit, never where a directory should.
#
# Measured over 2310 directories in 37 corpora across ten languages, the wider set
# `:incoherent_package` was calibrated over. A directory is narrow: the pooled median is 1
# child, the p95 is 17 and the p99 is 40. So `warn` at 25 reports 2.4% of directories and
# `high` at 40 reports 1.1%, which sits beside `file_length`'s 1.4% of files at its own high
# edge. Over the nine corpora alone, 132 directories, the same edges report 7.6% and 3.8%,
# the spread coming from guava, whose flat Java layout runs to a 216-child directory.
#
# This package's own `src` holds 40 children and lands on the high edge. That is the reason
# the rule ships off rather than a reason to raise the band: a band chosen to clear the
# author's own repository is not a measurement. It also reads lower than a file listing
# does, since the 34 queries under `src/queries` are `.scm` and the pattern tables are
# `.toml`, and a scan counts the files it parses, so `src/queries` is not a directory this
# rule can see at all.
#
# Two readings were measured and not shipped. Imbalance, as a Gini coefficient over a
# directory's children by line count, separates almost nothing: of 107 multi-child
# directories in the nine, 14 score above 0.6, and 13 of those already hold a file at
# `file_length`'s warn edge. Overlap with `:divisible_package` is the other, and it is what
# makes the two a pair rather than one restating the other: of 29 directories this reports
# over the nine and the wider Julia and Python corpora, 5 are directories
# `:divisible_package` also reports.
const CHILD_COUNT_BAND = (25, 40)

# The corpus needs this many scored directories before the percentile means anything; under
# it only the absolute band fires, as the other directory rules do on a thin corpus.
const MIN_CHILD_COUNT_DIRS = 5

# What `dir` holds directly: how many children are files, how many are subdirectories, how
# many lines sit under it in all, and the corpus node standing for it. Every file under
# `dir` contributes its lines, since a subdirectory's contents are part of what the
# directory holds, while only the child it sits in is counted as a child.
#
# `fg.files` is sorted, so the first file the walk meets is the earliest one the directory
# holds, the site the finding is reported at. Every directory reaches this walk from a file
# path, so there is always one.
function direct_children(fg::FileGraph, dir::AbstractString, lines::Dict{String, Int})
    children = Set{String}()
    subdirs = 0
    loc = 0
    anchor = 0
    for (node, path) in enumerate(fg.files)
        child = child_of(path, dir)
        child === nothing && continue
        loc += lines[path]
        anchor == 0 && (anchor = node)
        child in children && continue
        push!(children, child)
        child == path || (subdirs += 1)
    end
    return (length(children) - subdirs, subdirs, loc, anchor)
end

"""
    cluster_child_count(files, fg; band=$CHILD_COUNT_BAND, cut=0.95, min_dirs=$MIN_CHILD_COUNT_DIRS) -> Vector{Finding}

Directories holding more direct children than a reader can take in at once, reported as
`:child_count`. The
score is the number of direct children, a child file and a child subdirectory counting
one each, which is the node set [`cluster_divisible_packages`](@ref) reads. Each finding
carries the absolute `band` on that count and the corpus percentile, fired when either
trips; the percentile is read only once the corpus holds `min_dirs` scored directories.

The one location is the earliest file the directory holds, at that file's first unit, since
a finding points at code rather than at a path. Its label carries what the score leaves
out: the split between files and subdirectories, and the lines under the directory in all.

The finding names a rearrangement rather than a bounded edit, so the pass is off by
default: enable it with `child_count = true` under `[rules]` in a `.dendro.toml`.

Failure modes:

  - A directory of one subdirectory scores 1, and a chain of such directories is a real
    layout defect the count reads as the tidiest layout there is.
  - Lines are in the label and not in the score, so a directory of twelve thousand-line
    files reads the same as one of twelve ten-line files. `:file_length` is what reads the
    files.
  - The count sees the files a scan parses and nothing else, so a directory of assets, or
    of queries a grammar has no profile for, reads as though it held nothing. Against that,
    every language a scan does parse contributes, since the reading is the corpus paths and
    never the references.
"""
function cluster_child_count(
        files::Vector{ParsedFile}, fg::FileGraph;
        band::Tuple{Int, Int} = CHILD_COUNT_BAND, cut::Real = 0.95,
        min_dirs::Int = MIN_CHILD_COUNT_DIRS
    )
    directives = Dict{String, Vector{Directive}}(f.file => f.directives for f in files)
    lines = Dict{String, Int}(f.file => physical_lines(f.source) for f in files)
    scored = Tuple{Int, Vector{Location}}[]
    for dir in corpus_directories(fg)
        nfiles, nsubdirs, loc, anchor = direct_children(fg, dir, lines)
        label = "$dir, $nfiles files, $nsubdirs subdirectories, $loc lines"
        locations = Location[Location(fg.files[anchor], fg.first_line[anchor], "", label)]
        push!(scored, (nfiles + nsubdirs, locations))
    end
    return directory_findings(
        RELATIONAL.child_count, scored, directives, band, cut, length(scored) >= min_dirs
    )
end
