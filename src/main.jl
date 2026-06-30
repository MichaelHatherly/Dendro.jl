# Command-line entry. `julia -m Dendro <path>...` and the installed `dendro` app both
# call `main`, which parses arguments into options, runs `analyze`, prints the report,
# and returns an exit code. The CLI is the human-facing surface the config cascade
# reads from: run it in a repo with a `.dendro.toml` and the bands come from there.

# A usage error: a bad flag or a missing value. Carried as an exception so parsing
# stays a flat loop rather than threading an error code through every branch.
struct CLIError <: Exception
    msg::String
end

# Parsed command line. A path list plus the flags `analyze` and the report need.
struct CLIOptions
    paths::Vector{String}
    base::Union{Nothing, String}
    config_file::Union{Nothing, String}
    use_config::Bool
    cut::Union{Nothing, Float64}
    format::Symbol
    check::Bool
end

# A flag's value: from `--flag=value` when given inline, else the next token.
function take_value!(argv, name, inline)
    inline !== nothing && return inline
    isempty(argv) && throw(CLIError("option $name requires a value"))
    return popfirst!(argv)
end

# The output format symbol for a `--format` value.
function parse_format(value)
    value == "text" && return :text
    value == "github" && return :github
    throw(CLIError("--format must be text or github, got $value"))
end

# The percentile cutoff for a `--cut` value, a clean usage error on a non-number.
function parse_cut(value)
    n = tryparse(Float64, value)
    n === nothing && throw(CLIError("--cut must be a number, got $value"))
    return n
end

# Parse argv into options, throwing `CLIError` on a bad flag or missing value. `--help`
# and `--version` are handled before this, so every remaining `--flag` is an option or
# an error and every bare token is a path.
function parse_args(argv)
    paths = String[]
    base = config_file = nothing
    use_config = true
    cut = nothing
    format = :text
    check = false
    while !isempty(argv)
        x = popfirst!(argv)
        inline = nothing
        if startswith(x, "--") && occursin('=', x)
            parts = split(x, '='; limit = 2)
            x, inline = String(parts[1]), String(parts[2])
        end
        if x == "--no-config"
            use_config = false
        elseif x == "--check"
            check = true
        elseif x == "--base"
            base = take_value!(argv, x, inline)
        elseif x == "--config"
            config_file = take_value!(argv, x, inline)
        elseif x == "--cut"
            cut = parse_cut(take_value!(argv, x, inline))
        elseif x == "--format"
            format = parse_format(take_value!(argv, x, inline))
        elseif startswith(x, "-") && x != "-"
            throw(CLIError("unknown option $x"))
        else
            push!(paths, x)
        end
    end
    isempty(paths) && throw(CLIError("no paths given"))
    !use_config && config_file !== nothing &&
        throw(CLIError("--no-config and --config are contradictory"))
    return CLIOptions(paths, base, config_file, use_config, cut, format, check)
end

# Write the findings in the requested format: the REPL table or GitHub annotations.
function emit_report(findings, format)
    format === :github ? github_annotations(stdout, findings) :
        show(stdout, MIME("text/plain"), findings)
    println(stdout)
    return nothing
end

# Resolve config, analyze, print, and return the exit code. With `--check` the run
# gates on the `:high` floor, the error-severity findings (high-band scalars and all
# flags), exiting 1 when any remain and 0 on a clean floor. This is the satisfiable
# gate `errors` computes; the percentile-ranked `analyze` report is never empty, so it
# is the default triage output, not the gate. Paths and an explicit config are checked
# here, the CLI boundary, so a bad one is a clean usage error rather than a stack trace.
function run_cli(options::CLIOptions)
    options.config_file === nothing || isfile(options.config_file) ||
        throw(CLIError("config file not found: $(options.config_file)"))
    for path in options.paths
        ispath(path) || throw(CLIError("no such path: $path"))
    end
    config = discover_config(options.paths; explicit = options.config_file, use_files = options.use_config)
    findings = active(analyze(options.paths; base = options.base, config = config, cut = options.cut))
    if options.check
        gated = high_floor(findings)
        emit_report(gated, options.format)
        return isempty(gated) ? 0 : 1
    end
    emit_report(findings, options.format)
    return 0
end

function print_help()
    print(
        stdout,
        """
        dendro - a structural code-quality gate

        Usage: dendro [options] <path>...

        Options:
          --base=<ref>     report only findings on lines changed against <ref>
          --config=<file>  read <file> instead of a discovered .dendro.toml
          --no-config      ignore .dendro.toml, score against built-in defaults
          --cut=<float>    percentile cutoff for corpus-relative flags (default 0.95)
          --format=<fmt>   output format: text (default) or github
          --check          exit 1 when any finding is reported
          --version        print version and exit
          --help, -h       print this message and exit
        """,
    )
    return nothing
end

print_version() = println(stdout, "dendro ", pkgversion(@__MODULE__))

"""
    main(argv) -> Cint

The CLI entry point behind `julia -m Dendro` and the `dendro` app. Parses `argv`,
analyzes the given paths, prints the report, and returns an exit code: 0 normally, 1
on a usage error or when `--check` finds something.
"""
function main(argv)
    args = collect(String, argv)
    ("--help" in args || "-h" in args) && (print_help(); return Cint(0))
    "--version" in args && (print_version(); return Cint(0))
    try
        return Cint(run_cli(parse_args(args)))
    catch err
        err isa CLIError || err isa ConfigError || err isa TOML.ParserError || rethrow()
        msg = err isa TOML.ParserError ? sprint(showerror, err) : err.msg
        println(stderr, "dendro: ", msg)
        return Cint(1)
    end
end

@static if isdefined(Base, Symbol("@main"))
    @main
end
