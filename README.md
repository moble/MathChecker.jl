# MathChecker

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://moble.github.io/MathChecker.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://moble.github.io/MathChecker.jl/dev)
[![Test workflow status](https://github.com/moble/MathChecker.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/moble/MathChecker.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/moble/MathChecker.jl)
[![Lint workflow Status](https://github.com/moble/MathChecker.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/moble/MathChecker.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/moble/MathChecker.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

*Floating-point numbers that check their own arithmetic.*

> **Written with Claude.** The design of this package was specified by
> me, Mike Boyle, but the implementation, tests, and this
> documentation were produced by Anthropic's Claude, and then I
> reviewed it.  Please read the code with that in mind, and report
> anything suspicious as an issue.

`Checked{T}` wraps a floating-point number and behaves exactly like it
— except that after every operation, the checks selected by its type
parameters inspect the result and throw an error pointing at the
offending operation:

```julia
Checked{T, Precision, NaN, Inf, Cancellation, Absorption, Subnormal, Rounding}
```

| Flag           | Signals when …                                              |
|:---------------|:------------------------------------------------------------|
| `Precision`    | mixed with a float of a different type (a dispatch error)   |
| `NaN`          | a `NaN` is produced, or used as an operand                  |
| `Inf`          | `±Inf` is produced                                          |
| `Cancellation` | an addition or subtraction cancels most significant bits    |
| `Absorption`     | an addend is too small to change the result                 |
| `Subnormal`    | a subnormal number is produced                              |
| `Rounding`     | `+`, `-`, `*`, `/`, or `sqrt` is not exact                  |

Checks that are turned off are eliminated by the compiler, so a
`Checked{Float64}` with every flag off compiles to the same
instructions as a `Float64`.

```julia
julia> using MathChecker

julia> x = Checked(1.0);                   # Precision, NaN, and Inf checks on by default

julia> unchecked(sqrt(x + 1) * 2)
2.8284271247461903

julia> x / 0
ERROR: InfError: 1.0 / 0.0 produced Inf:
       division by zero (the exact result is infinite).

julia> Checked{Float32}(1) + 0.5           # a Float64 literal in a Float32 computation
ERROR: MethodError: no method matching mixed_precision(::MathChecker.PrecisionMismatch{...}, ::Float64)
...
MathChecker: the type Checked{Float32, true, true, true, false, false, false, false} has the `Precision`
check enabled, which forbids implicitly mixing it with Float64. ...

julia> (1 + checked(1e-9; cancellation=true)) - 1
ERROR: CancellationError: 1.000000001 - 1.0 produced 1.000000082740371e-9,
       cancelling 29.9 of 53 significant bits: |result| / max(|a|, |b|) = 1e-09
       is below the tolerance 1.49e-08 (26 bits).
```

`checked` and `unchecked` work elementwise on arrays, tuples, and
complex numbers, so an existing function can be checked without
modification, and `collect_failures` runs a computation to completion
while recording every failed check:

```julia
result, failures = collect_failures() do
    unchecked(myfunction(checked(A; absorption=true, cancellation=1e-3)))
end
```

See the [documentation](https://moble.github.io/MathChecker.jl/dev)
for the precise semantics of each check, the handler mechanism, and
design notes.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/moble/MathChecker.jl")
```

## Acknowledgements

This package was written by Claude (Anthropic) in Claude Code, from a
design brief and under the direction of Michael Boyle; see the notice
at the top of this file.

The `NaN` check generalizes the `NaNCheck` type from [a Julia
Discourse post by Brian
Guenter](https://discourse.julialang.org/t/treating-nan-as-error-helping-debugging/36933/9).  That post, ultimately, inspired this package.

## Related packages

+ [TrackedFloats.jl](https://github.com/utahplt/TrackedFloats.jl) is
  the closest relative: `TrackedFloat64` and friends also wrap a float
  and watch every operation for `NaN` and `Inf`.  It logs each event
  (with a stack trace) to a file rather than throwing, classifies
  events as *generation*, *propagation*, or *kill* (an exceptional
  value silently disappearing, e.g. `NaN < 1.0 → false`), and can
  *inject* `NaN`s at random to fuzz a program's handling of them.
  MathChecker covers more conditions (precision mixing, cancellation,
  absorption, underflow, inexactness), selects them at compile time so
  that unused checks cost nothing, and works for any `AbstractFloat`.
+ [NaNMath.jl](https://github.com/JuliaMath/NaNMath.jl) makes
  functions *return* NaN instead of throwing `DomainError`s — the
  opposite philosophy.
+ [StochasticRounding.jl](https://github.com/milankl/StochasticRounding.jl)
  and
  [StochasticArithmetic.jl](https://github.com/ffevotte/StochasticArithmetic.jl)
  estimate rounding error statistically by perturbing every rounding;
  MathChecker detects it deterministically with error-free
  transformations.
+ [AccurateArithmetic.jl](https://github.com/JuliaMath/AccurateArithmetic.jl)
  provides the error-free transformations (TwoSum, TwoProd) that the
  `Rounding` check is built on, as well as compensated summation and
  dot products.
+ [IntervalArithmetic.jl](https://github.com/JuliaIntervals/IntervalArithmetic.jl)
  bounds the error of a whole computation rigorously; MathChecker
  instead flags individual suspicious operations.
+ [OverflowContexts.jl](https://github.com/BioTurboNick/OverflowContexts.jl)
  does for integer overflow what MathChecker does for floating-point
  trouble, by rewriting expressions rather than wrapping values.
