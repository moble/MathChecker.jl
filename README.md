# MathChecker

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://moble.github.io/MathChecker.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://moble.github.io/MathChecker.jl/dev)
[![Test workflow status](https://github.com/moble/MathChecker.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/moble/MathChecker.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/moble/MathChecker.jl)
[![Lint workflow Status](https://github.com/moble/MathChecker.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/moble/MathChecker.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

*Floating-point numbers that check their own arithmetic.*

`Checked{T}` wraps a floating-point number and behaves exactly like it — except that
after every operation, the checks selected by its type parameters inspect the result and
throw an error pointing at the offending operation:

```julia
Checked{T, Precision, NaN, Inf, Cancellation, Swamping, Subnormal, Rounding}
```

| Flag           | Signals when …                                              |
|:---------------|:------------------------------------------------------------|
| `Precision`    | mixed with a float of a different type (a dispatch error)   |
| `NaN`          | a `NaN` is produced or compared                             |
| `Inf`          | `±Inf` is produced                                          |
| `Cancellation` | an addition or subtraction cancels most significant bits    |
| `Swamping`     | an addend is too small to change the result                 |
| `Subnormal`    | a subnormal number is produced                              |
| `Rounding`     | `+`, `-`, `*`, `/`, or `sqrt` is not exact                  |

Checks that are turned off are eliminated by the compiler, so a `Checked{Float64}` with
every flag off compiles to the same instructions as a `Float64`.

```julia
julia> using MathChecker

julia> x = Checked{Float64}(1.0);          # Precision, NaN, and Inf checks on by default

julia> unchecked(sqrt(x + 1) * 2)
2.8284271247461903

julia> x / 0
ERROR: InfError: 1.0 / 0.0 produced Inf.

julia> Checked{Float32}(1) + 0.5           # a Float64 literal in a Float32 computation
ERROR: MethodError: no method matching mixed_precision(::MathChecker.PrecisionMismatch{...}, ::Float64)
...
MathChecker: the type Checked{Float32, true, true, true, false, false, false, false} has the `Precision`
check enabled, which forbids implicitly mixing it with Float64. ...

julia> (1 + checked(1e-9; cancellation=true)) - 1
ERROR: CancellationError: 1.000000001 - 1.0 produced 1.000000082740371e-9,
       cancelling 29.9 of 53 significant bits: |result| / max(|a|, |b|) = 1.0e-9
       is below the tolerance 1.49e-8 (26 bits).
```

`checked` and `unchecked` work elementwise on arrays, tuples, and complex numbers, so an
existing function can be checked without modification, and `collect_failures` runs a
computation to completion while recording every failed check:

```julia
result, failures = collect_failures() do
    unchecked(myfunction(checked(A; swamping=true, cancellation=1e-3)))
end
```

See the [documentation](https://moble.github.io/MathChecker.jl/dev) for the precise
semantics of each check, the handler mechanism, and design notes.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/moble/MathChecker.jl")
```

## Acknowledgements

The `NaN` check generalizes the `NaNCheck` type from
[a Julia Discourse post by Brian Guenter](https://discourse.julialang.org/t/treating-nan-as-error-helping-debugging/36933/9).
