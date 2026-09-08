```@meta
CurrentModule = MathChecker
```

# MathChecker

*Floating-point numbers that check their own arithmetic.*

!!! warning "Written with Claude"
    The design of this package was specified by me, Mike Boyle, but
    the implementation, tests, and this documentation were produced by
    [Claude](https://claude.ai) (Anthropic's AI model) working in
    Claude Code, and then I reviewed it.  Please read the code with
    that in mind, and report anything suspicious as an issue.

MathChecker provides one type, [`Checked`](@ref), which wraps any
floating-point number and behaves exactly like it in arithmetic —
except that after every operation, a set of checks selected by the
type's parameters inspects the result and signals an error that points
at the offending operation.  The checks are:

| Flag           | Signals when …                                                |
|:---------------|:--------------------------------------------------------------|
| `Precision`    | the value is implicitly mixed with a float of a different type |
| `NaN`          | a `NaN` is produced, or compared with `<`, `<=`, `>`, `>=`     |
| `Inf`          | `±Inf` is produced                                             |
| `Cancellation` | an addition or subtraction cancels most of its significant bits |
| `Swamping`     | an addend is too small to change the result                    |
| `Subnormal`    | a subnormal number is produced                                 |
| `Rounding`     | `+`, `-`, `*`, `/`, or `sqrt` is not exact                     |

Because the flags are type parameters, checks that are turned off are
eliminated by the compiler: a `Checked{Float64}` with every flag off
compiles to the same instructions as a `Float64`.

## Installation

The package is not yet registered.  Install it from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/moble/MathChecker.jl")
```

## Quick start

Wrap the inputs of a computation and run it as usual:

```jldoctest quickstart
julia> using MathChecker

julia> x = Checked{Float64}(1.0)
Checked{Float64}(1.0)

julia> y = sqrt(x + 1) * 2       # ordinary arithmetic, checked at every step
Checked{Float64}(2.8284271247461903)

julia> unchecked(y)              # get the plain value back
2.8284271247461903
```

By default the `Precision`, `NaN`, and `Inf` checks are on — the three
that never produce false positives.  When something goes wrong, the
error names the operation and its operands:

```jldoctest quickstart
julia> x / 0
ERROR: InfError: 1.0 / 0.0 produced Inf:
       division by zero (the exact result is infinite).
[...]

julia> (x - 1) / (x - 1)
ERROR: NaNError: 0.0 / 0.0 produced NaN.
[...]

julia> Checked{Float32}(1) + 0.5     # a Float64 literal contaminating a Float32 computation
ERROR: MethodError: no method matching mixed_precision(::MathChecker.PrecisionMismatch{Checked{Float32, true, true, true, false, false, false, false}, Float64}, ::Float64)
[...]
```

The other checks are enabled with keyword arguments to [`checked`](@ref) (or, equivalently,
as positional type parameters):

```jldoctest quickstart
julia> z = checked(1e-9; cancellation=true)
Checked{Float64, true, true, true, true, false, false, false}(1.0e-9)

julia> (1 + z) - 1
ERROR: CancellationError: 1.000000001 - 1.0 produced 1.000000082740371e-9,
       cancelling 29.9 of 53 significant bits: |result| / max(|a|, |b|) = 1e-09
       is below the tolerance 1.49e-08 (26 bits).
[...]
```

`checked` and `unchecked` also work elementwise on arrays, tuples, and complex numbers, so
an existing function can be checked without modification:

```julia
result = unchecked(myfunction(checked(A; swamping=true), checked(b; swamping=true)))
```

To see *all* of the problems in a computation rather than stopping at
the first, use [`collect_failures`](@ref) (or another [handler](@ref
handling-failures)):

```jldoctest quickstart
julia> result, failures = collect_failures() do
           w = checked(1.0)
           (w / 0) * 0
       end;

julia> failures
2-element Vector{CheckError}:
 InfError(/, Inf, (1.0, 0.0))
 NaNError(*, NaN, (Inf, 0.0))
```

## Uses

- **Hunting a `NaN` or `Inf`.** Wrap the inputs, and the first
  operation that produces a non-finite value throws, with a stack
  trace to the line that did it.  (This use, and the original
  implementation, come from [a Discourse post by Brian
  Guenter](https://discourse.julialang.org/t/treating-nan-as-error-helping-debugging/36933/9).)
- **Detecting the use of uninitialized memory.** Fill an array with
  `Checked{Float64}(NaN)`; constructors never signal, but the first
  arithmetic on an element that was never assigned will.
- **Keeping a `Float32`, `Double64`, or `BigFloat` computation pure.**
  With the `Precision` check, a stray `Float64` literal — the classic
  way to silently lose the extra precision of a `Double64` — becomes
  an error at the offending operation, with a hint explaining how to
  fix it.
- **Locating loss of precision.** The `Cancellation` and `Swamping`
  checks point at the additions and subtractions where relative
  accuracy is destroyed, and the `Rounding` check verifies that steps
  which are *meant* to be exact really are.

## Contents

```@contents
Pages = ["10-checks.md", "20-handling-failures.md", "30-design.md", "95-reference.md"]
Depth = 2
```
