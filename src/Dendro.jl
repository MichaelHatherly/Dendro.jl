module Dendro

import NearestNeighbors
import RelocatableFolders
import TOML
import TreeSitter

public analyze, active, errors, github_annotations, mermaid
public Finding, Findings, Location
public Rule, BUILTIN_RULES, OPTIONAL_RULES
public Config

include("resolve.jl")
include("parallel.jl")
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
include("unreferenced.jl")
include("cohesion.jl")
include("ignore.jl")
include("config.jl")
include("corpus.jl")
include("gate.jl")
include("mermaid.jl")
include("main.jl")

end # module
