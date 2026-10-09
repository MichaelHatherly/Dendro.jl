# How long a file is. Every other scalar Dendro reports measures a definition, a subject
# with a first line and a name; this one measures the file itself, which has neither a site
# inside it to point at nor a boundary an author drew around it. So the finding sits on line
# 1 and the edit it names is a split.
#
# Physical lines, blanks and comments included. That is the reading the published file-size
# limits are written in and the reading a reviewer scrolls through, and it is the same count
# `corpus_scores` divides verbosity by, so one notion of a file's size serves both.
#
# Scored like cohesion: an absolute band on the count and the corpus percentile, fired when
# either trips.

# Absolute band on a file's physical line count.
#
# Both edges are published limits rather than corpus statistics, the bands stance. ESLint's
# `max-lines` defaults to 300 code lines and SonarQube's to 750; converted to physical lines
# those bracket `warn` at 500. Checkstyle's `FileLength` defaults to 2000 and counts every
# line already, which is `high`. The measurement says what those levels cost, never where
# they sit.
#
# Measured over 1183 files in nine corpora across five languages: this package,
# DataFrames.jl, HTTP.jl, CommonMark.jl, flask, requests, fastmcp, ripgrep and guava,
# gathered through the `ignore` and generated-file filters a scan applies. A long file is
# ordinary. The pooled median is 171 lines and the p90 is 768, so `warn` reports 19.1% of
# files pooled and 58.1% of HTTP.jl's, which is a fixed target doing its job on a corpus
# that sits above it: nothing at `warn` reaches the gate.
#
# `high` is where the cost lands, since that band is the floor every dogfooding package
# gates on. 1000 puts 6.3% of files pooled into it and 29.0% of HTTP.jl's. `:scattered` was
# retuned away from that level for the same reason. 2000 puts 1.4% there,
# beside `function_length`'s 0.6% of definitions over the same corpora, and it names the
# files nobody argues about: ripgrep's 7779-line `defs.rs`, guava's 4985-line
# `LocalCache.java`, DataFrames.jl's 2996-line `abstractdataframe.jl`. Below it the
# percentile carries the corpus-relative signal, which still reports the longest file in a
# corpus whose worst is a 600.
#
# A generated data table written out by hand, CommonMark.jl's 2233-line entity map, clears
# 2000 and is answered with a `dendro-ignore-file`, not a lower band.
const FILE_LENGTH_BAND = (500, 2000)

# The corpus needs this many files before the line-count percentile means anything; under it
# only the absolute band fires, as cohesion does on a thin corpus.
const MIN_FILE_LENGTH_FILES = 5

"""
    cluster_file_length(files; band=$FILE_LENGTH_BAND, cut=0.95, min_files=$MIN_FILE_LENGTH_FILES) -> Vector{Finding}

Files too long to hold as one thing, reported as `:file_length`. The score is the file's
physical line count, blanks and comments included. Each finding carries both scores, the
absolute `band` on that count and the corpus percentile, fired when either trips; the
percentile is read only once the corpus holds `min_files` files.

The one location is line 1, since a file carries no site inside it that stands for the
whole. That is what makes the finding coarse under `analyze(; base)`, which keeps a finding
only where a changed line falls: an edit in the middle of a long file does not re-report its
length. The `--since` ratchet is the surface that reads this rule on a change, since its key
is the location set rather than a line range.
"""
function cluster_file_length(
        files::Vector{ParsedFile}; band::Tuple{Int, Int} = FILE_LENGTH_BAND,
        cut::Real = 0.95, min_files::Integer = MIN_FILE_LENGTH_FILES
    )
    scored = Tuple{ParsedFile, Int, Vector{Location}}[
        (f, physical_lines(f.source), Location[Location(f.file, 1, "")]) for f in files
    ]
    return scored_findings(RELATIONAL.file_length, scored, band, cut, min_files)
end
