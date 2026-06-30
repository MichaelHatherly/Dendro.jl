# Benchmark comparison script
# Generates markdown report comparing two benchmark results

import JSON
import Printf: @sprintf

# Allocations and memory are deterministic: the same code on the same input always
# produces the same counts, so a change past this tolerance is real, never noise.
const DETERMINISTIC_TOLERANCE = 0.01
# Wall-clock carries measurement and runner noise even after normalization, so it
# needs a wider band before a change counts as a regression.
const TIME_TOLERANCE = 0.1

function load_results(path)
    return JSON.parse(read(path, String))
end

# Median wall-clock of the fixed calibration kernel, or `nothing` if the result
# predates it. The kernel does identical work every run, so its time is a direct
# read of how fast the runner was that day.
function calibration_median(doc)
    benchmarks = get(doc, "benchmarks", Dict())
    calib = get(benchmarks, "calibration", nothing)
    calib === nothing && return nothing
    return get(get(calib, "time_ns", Dict()), "median", nothing)
end

# Factor that scales `curr`'s wall-clock onto `base`'s clock, cancelling the
# runner-speed difference between the two runs. Returns 1.0 when either side lacks
# calibration, leaving times un-normalized.
function normalization_factor(base, curr)
    base_calib = calibration_median(base)
    curr_calib = calibration_median(curr)
    (base_calib === nothing || curr_calib === nothing || curr_calib == 0) && return 1.0
    return base_calib / curr_calib
end

# Ratio of current to baseline, where >1 means the metric grew (worse, since lower
# is better for time, memory, and allocations). A zero baseline maps any growth to
# infinity and a flat zero to 1.
function metric_ratio(base, curr)
    base == 0 && return curr == 0 ? 1.0 : Inf
    return curr / base
end

verdict(ratio) = ratio > 1 ? :regression : :improvement

# Classify one benchmark. Deterministic signals (allocations, then memory) decide
# the verdict when either moves past its tolerance, since they cannot be runner
# noise. Otherwise the runner-normalized time decides, catching a compute regression
# that touches no allocation. `factor` comes from `normalization_factor`.
function classify(base, curr; factor)
    alloc_ratio = metric_ratio(base["allocations"], curr["allocations"])
    mem_ratio = metric_ratio(base["memory_bytes"], curr["memory_bytes"])
    time_ratio = metric_ratio(base["time_ns"]["median"], curr["time_ns"]["median"] * factor)

    det_ratio, det_signal = abs(alloc_ratio - 1) >= abs(mem_ratio - 1) ?
        (alloc_ratio, :allocations) : (mem_ratio, :memory)

    status, signal = if abs(det_ratio - 1) > DETERMINISTIC_TOLERANCE
        (verdict(det_ratio), det_signal)
    elseif abs(time_ratio - 1) > TIME_TOLERANCE
        (verdict(time_ratio), :time)
    else
        (:neutral, :none)
    end
    return (; status, signal, alloc_ratio, mem_ratio, time_ratio)
end

function format_time(ns)
    return if ns < 1_000
        @sprintf("%.1f ns", ns)
    elseif ns < 1_000_000
        @sprintf("%.2f μs", ns / 1_000)
    elseif ns < 1_000_000_000
        @sprintf("%.2f ms", ns / 1_000_000)
    else
        @sprintf("%.2f s", ns / 1_000_000_000)
    end
end

function format_memory(bytes)
    return if bytes < 1024
        @sprintf("%d B", bytes)
    elseif bytes < 1024^2
        @sprintf("%.1f KiB", bytes / 1024)
    elseif bytes < 1024^3
        @sprintf("%.1f MiB", bytes / 1024^2)
    else
        @sprintf("%.1f GiB", bytes / 1024^3)
    end
end

function format_change(baseline, current)
    if baseline == 0
        return "N/A"
    end
    ratio = current / baseline
    pct = (ratio - 1) * 100
    return if abs(pct) < 1
        "~"
    elseif pct > 0
        @sprintf("+%.1f%%", pct)
    else
        @sprintf("%.1f%%", pct)
    end
end

status_emoji(status) =
    status == :regression ? "🔴" : status == :improvement ? "🟢" : "⚪"

# One-line summary of a classified change, quoting the metric that drove the verdict.
function describe_change(name, base, curr, factor, c)
    return if c.signal == :allocations
        "$name: $(base["allocations"]) → $(curr["allocations"]) allocs ($(format_change(base["allocations"], curr["allocations"])))"
    elseif c.signal == :memory
        "$name: $(format_memory(base["memory_bytes"])) → $(format_memory(curr["memory_bytes"])) ($(format_change(base["memory_bytes"], curr["memory_bytes"])))"
    else
        base_time = base["time_ns"]["median"]
        norm_time = curr["time_ns"]["median"] * factor
        "$name: $(format_time(base_time)) → $(format_time(norm_time)) normalized ($(format_change(base_time, norm_time)))"
    end
end

# Header line reporting how much the runner's speed differed between the two runs,
# which the time column is normalized against.
function calibration_note(baseline, current, factor)
    base_calib = calibration_median(baseline)
    curr_calib = calibration_median(current)
    if base_calib === nothing || curr_calib === nothing
        return "**Runner calibration:** unavailable; time deltas are raw."
    end
    pct = (1 / factor - 1) * 100
    direction = pct >= 0 ? "slower" : "faster"
    return @sprintf(
        "**Runner calibration:** base %s, current %s (current %.1f%% %s). Time deltas are normalized to the baseline runner.",
        format_time(base_calib),
        format_time(curr_calib),
        abs(pct),
        direction,
    )
end

function compare_and_report(baseline_path, current_path, output_path)
    baseline = load_results(baseline_path)
    current = load_results(current_path)

    base_benchmarks = baseline["benchmarks"]
    curr_benchmarks = current["benchmarks"]
    factor = normalization_factor(baseline, current)

    # Collect all benchmark names
    all_names = union(keys(base_benchmarks), keys(curr_benchmarks))
    sorted_names = sort(collect(all_names))

    io = IOBuffer()

    println(io, "## Benchmark Comparison")
    println(io)
    println(
        io,
        "**Baseline:** `$(get(get(baseline, "git", Dict()), "commit", "unknown")[1:min(7, end)])`",
    )
    println(
        io,
        "**Current:** `$(get(get(current, "git", Dict()), "commit", "unknown")[1:min(7, end)])`",
    )
    println(io)
    println(io, calibration_note(baseline, current, factor))
    println(io)

    # Summary table
    println(io, "### Summary")
    println(io)
    println(
        io,
        "| Benchmark | Base Time | Cur Time | Δ Time (norm) | Base Mem | Cur Mem | Δ Mem | Base Alloc | Cur Alloc | Δ Alloc | Status |",
    )
    println(
        io,
        "|-----------|-----------|----------|---------------|----------|---------|-------|------------|-----------|---------|--------|",
    )

    regressions = String[]
    improvements = String[]

    for name in sorted_names
        base = get(base_benchmarks, name, nothing)
        curr = get(curr_benchmarks, name, nothing)

        if base === nothing || curr === nothing
            label = base === nothing ? "new" : "removed"
            println(io, "| $name | - | - | - | - | - | - | - | - | - | ⚪ $label |")
            continue
        end

        base_time = base["time_ns"]["median"]
        curr_time = curr["time_ns"]["median"]
        base_mem = base["memory_bytes"]
        curr_mem = curr["memory_bytes"]
        base_alloc = base["allocations"]
        curr_alloc = curr["allocations"]

        c = classify(base, curr; factor)
        time_change = format_change(base_time, curr_time * factor)
        mem_change = format_change(base_mem, curr_mem)
        alloc_change = format_change(base_alloc, curr_alloc)

        if c.status == :regression
            push!(regressions, describe_change(name, base, curr, factor, c))
        elseif c.status == :improvement
            push!(improvements, describe_change(name, base, curr, factor, c))
        end

        println(
            io,
            "| $name | $(format_time(base_time)) | $(format_time(curr_time)) | $time_change | $(format_memory(base_mem)) | $(format_memory(curr_mem)) | $mem_change | $base_alloc | $curr_alloc | $alloc_change | $(status_emoji(c.status)) |",
        )
    end

    println(io)

    if !isempty(regressions)
        println(io, "### ⚠️ Regressions")
        println(io)
        for r in regressions
            println(io, "- $r")
        end
        println(io)
    end

    if !isempty(improvements)
        println(io, "### 🎉 Improvements")
        println(io)
        for i in improvements
            println(io, "- $i")
        end
        println(io)
    end

    # Legend
    println(io, "<details>")
    println(io, "<summary>Legend</summary>")
    println(io)
    println(io, "Allocations and memory are deterministic, so a change past 1% is a")
    println(io, "real change and drives the verdict. Time decides only when those are")
    println(io, "flat, and is normalized to the baseline runner before a 10% band applies.")
    println(io)
    println(io, "- 🟢 Improvement")
    println(io, "- 🔴 Regression")
    println(io, "- ⚪ No significant change")
    println(io)
    println(io, "</details>")

    result = String(take!(io))
    write(output_path, result)
    println(result)
    println("Comparison written to: $output_path")
    return result
end
