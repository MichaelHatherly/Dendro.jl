module Dendro

import TreeSitter
import JSON

export analyze, analyze_diff, build_baseline, save_baseline, load_baseline, report
export Finding, Baseline, active

include("resolve.jl")
include("profile.jl")
include("profiles.jl")
include("units.jl")
include("metrics.jl")
include("flags.jl")
include("baseline.jl")
include("suppress.jl")
include("report.jl")
include("diff.jl")

end # module
