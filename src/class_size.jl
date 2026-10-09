# How much a class holds. `:divisible_class` asks whether a class's methods fall into
# several concerns; `:member_count` asks the question a reader asks first, before any
# reading of what the members share: is there too much here to hold as one thing. The edit
# it names is the one `:file_length` names a level up, a split.
#
# Constructors count. The cohesion rule drops them because a constructor assigns every field
# and would link every group to every other, but a class with fifteen constructors is what a
# size reading is for, so the exclusion belongs to that rule rather than to the member set
# both read off `class_methods`.
#
# Coverage follows the class reading and so do its limits. A language earns it by putting a
# class's methods inside the node declaring it, which is python, java, javascript,
# typescript, php, ruby and rust; Julia, Go, C and C++ tag no `@class` and score nothing.
# Nothing here resolves a type or a dispatch: the members are the callable units one
# syntactic container holds.
#
# Scored like cohesion: an absolute band on the count and the corpus percentile, fired when
# either trips.

# Absolute band on the number of members a class declares.
#
# `warn` follows the external anchor and `high` follows the measurement. Twenty methods is
# where the NOM guidance behind the God-class detectors puts "many", so that is `warn`. The
# literature names no second level, and `high` is the floor a dogfooding package gates on,
# so measurement sets it.
#
# Measured over 5478 classes in eight corpora across six languages: guava, flask, requests,
# fastmcp, ripgrep, laravel-framework, rails and the MCP TypeScript SDK. The last three
# join the five the other class rule was measured over because php, ruby and typescript
# were otherwise unrepresented. A small class is ordinary. The pooled median is 4 members
# and the p90 is 16, so `warn` at 20 reports 7.6% of classes pooled and 10.6% of laravel's,
# which is a fixed target doing its job on a corpus sitting above it. Nothing at `warn`
# reaches the gate.
#
# `high` is where the cost lands. At 40 it holds 2.1% of classes pooled, beside
# `:file_length`'s 1.4% of files over its own corpora, and it names the classes nobody
# argues about: laravel's 259-member `Builder`, rails' 161-member `AbstractAdapter`,
# guava's 91-member `LocalCache`. Reading the 38-to-44 band by hand found god classes and
# static utility piles throughout, guava's `Sets` and `Maps`, laravel's `Gate`, rails'
# `Base`. Thirty puts 3.8% of classes pooled and 6.5% of laravel's into the gate, the level
# `:scattered` was retuned away from. Below 40 the percentile carries the corpus-relative
# signal, which still reports the largest class in a corpus whose worst is a 25. The
# per-corpus p95 runs from 12 to 34 and the p99 from 24 to 99, so neither edge is a corpus
# statistic and the spread is why not.
const MEMBER_COUNT_BAND = (20, 40)

# The corpus needs this many scored classes before a class-size percentile means anything;
# under it only the absolute band fires, as cohesion does on a thin corpus.
const MIN_CLASS_COUNT = 5

"""
    ClassSubject

One class as a size rule reads it: the `file` holding it, the unit indices of its
`members`, and the `location` that stands for the class, its declaration line and name.
[`class_subjects`](@ref) pairs every class in the corpus with what the rule scores it from.
"""
struct ClassSubject
    file::ParsedFile
    members::Vector{Int}
    location::Location

    # Built only from values that already have these types, so the converting outer
    # constructor Julia would generate has no caller. Declaring this one keeps it
    # ungenerated, and with it the three `convert(::Type{...}, ::Any)` matches the sound
    # analyser counts once per field of a struct built anywhere in the package.
    ClassSubject(file::ParsedFile, members::Vector{Int}, location::Location) =
        new(file, members, location)
end

"""
    class_subjects(files) -> Vector{ClassSubject}

Every class in the corpus, in corpus order, paired with what a size rule scores it from.
Files whose language tags no `@class` contribute none.
"""
function class_subjects(files::Vector{ParsedFile})
    out = ClassSubject[]
    for f in files
        index = f.index
        isempty(index.class.nodes) && continue
        for (node, members) in class_methods(index)
            location = Location(f.file, line_of(node), held_class_name(node, index))
            push!(out, ClassSubject(f, members, location))
        end
    end
    return out
end


# What one class declares, the value `:member_count` scores. Named apart from the metric
# because `RELATIONAL` spells every metric out as a field name, and a definition sharing one
# would be what the name in `rules.jl` lexically resolves to, an edge the file graph then
# reads as a dependency back on this file.
declared_members(c::ClassSubject) = length(c.members)

"""
    cluster_class_size(files, band; cut=0.95, min_classes=$MIN_CLASS_COUNT) -> Vector{Finding}

Classes declaring more members than one class should. The members are the ones
[`class_methods`](@ref) attributes: a nested class takes its own, and a closure written
inside a method belongs to that method rather than to the class. Constructors are among
them, since the exclusion belongs to `:divisible_class` and not to the member set both read.

`band` is positional where every sibling pass takes it by keyword, which takes one report
off the sound analyser's reading of the keyword-argument lowering. Each finding carries both
scores, the absolute `band` and the corpus percentile over every class scored alongside it,
fired when either trips; the percentile is read only once the corpus holds `min_classes`
classes.

The one location is the class declaration, carrying the class name, and not one per member:
the edit a finding names is the class, and a member list would report the same class as many
times as it has members.

A language whose query tags no `@class` scores nothing, which is Julia, Go, C and C++, so a
corpus in one of those reports nothing here. The band comment on `MEMBER_COUNT_BAND` carries
the measurement behind the default.
"""
function cluster_class_size(
        files::Vector{ParsedFile}, band::Tuple{Int, Int};
        cut::Real = 0.95, min_classes::Integer = MIN_CLASS_COUNT
    )
    scored = Tuple{ParsedFile, Int, Vector{Location}}[
        (c.file, declared_members(c), Location[c.location]) for c in class_subjects(files)
    ]
    return scored_findings(RELATIONAL.member_count, scored, band, cut, min_classes)
end
