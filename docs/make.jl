using Documenter, RadioClock

makedocs(
    modules = [RadioClock],
    sitename = "RadioClock",
    pages    = [
        "Introduction" => "index.md",
    ],
    format = Documenter.HTML(
        ;
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
)

deploydocs(
    repo = "github.com/giordano/RadioClock.jl.git",
    target = "build",
    deps = nothing,
    make = nothing,
    push_preview = true,
)
