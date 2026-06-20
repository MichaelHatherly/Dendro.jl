# Profile Dendro analysis to find optimization targets
# Usage: julia --project=benchmark benchmark/profile.jl

import Dendro
import Profile

const CORPUS_DIR = joinpath(@__DIR__, "..", "test", "corpus")

# Warmup
Dendro.analyze(CORPUS_DIR)

# Profile with more iterations for better sampling
Profile.clear()
Profile.@profile for _ in 1:100
    Dendro.analyze(CORPUS_DIR)
end

# Write to file
open(joinpath(@__DIR__, "profile.txt"), "w") do io
    println(io, "=== FLAT PROFILE ===\n")
    Profile.print(io, format = :flat, sortedby = :count, mincount = 10)
    println(io, "\n\n=== TREE PROFILE ===\n")
    Profile.print(io, mincount = 10, noisefloor = 2.0)
end

println("Profile written to benchmark/profile.txt")
