module Dendro

import NearestNeighbors
import TreeSitter

public analyze, active, github_annotations
public Finding, Findings, Location
public Rule, BUILTIN_RULES

include("resolve.jl")
include("profile.jl")
include("profiles.jl")
include("units.jl")
include("metrics.jl")
include("flags.jl")
include("rules.jl")
include("baseline.jl")
include("suppress.jl")
include("report.jl")
include("diff.jl")
include("clones.jl")
include("corpus.jl")

end # module
