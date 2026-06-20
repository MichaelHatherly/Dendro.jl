# Quick benchmark for development iteration
# Usage: julia --project=benchmark benchmark/quick.jl

import Dendro
import BenchmarkTools: @btime

const CORPUS_DIR = joinpath(@__DIR__, "..", "test", "corpus")

println("Analyzing test corpus:")
@btime Dendro.analyze($CORPUS_DIR)

println("\nAllocation details:")
@time Dendro.analyze(CORPUS_DIR)
