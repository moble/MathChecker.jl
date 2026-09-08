# This simply uses `make.jl` in this directory to build the docs, then serves them locally.
# Run `julia --project=docs docs/serve.jl` from the top directory to execute this script.

import LiveServer: servedocs

servedocs(;
    include_dirs=["src/",],
    launch_browser=true,
)
