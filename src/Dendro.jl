module Dendro

import NearestNeighbors
import RelocatableFolders
import TreeSitter

public analyze, active, github_annotations
public Finding, Findings, Location
public Rule, BUILTIN_RULES, OPTIONAL_RULES

include("resolve.jl")
include("profile.jl")
include("profiles.jl")
include("bindings.jl")
include("query_index.jl")
include("units.jl")
include("graph_edges.jl")
include("metrics.jl")
include("flags.jl")
include("rules.jl")
include("baseline.jl")
include("suppress.jl")
include("parsed_file.jl")
include("report.jl")
include("diff.jl")
include("clones.jl")
include("naturalness.jl")
include("linkage.jl")
include("corpus_graph.jl")
include("placement.jl")
include("scattered.jl")
include("cohesion.jl")
include("ignore.jl")
include("corpus.jl")

end # module
