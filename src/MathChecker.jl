"""
    MathChecker

Floating-point numbers that check their own arithmetic.

Wrap a value in [`Checked`](@ref) and use it exactly as you would the underlying float.
After every operation, the checks selected by the type's flag parameters inspect the
result and signal an error pointing at the offending operation:

    Checked{T, Precision, NaN, Inf, Cancellation, Swamping, Subnormal, Rounding}

| Flag           | Signals when …                                          |
|:---------------|:--------------------------------------------------------|
| `Precision`    | mixed with a float of a different type (a dispatch error)|
| `NaN`          | a `NaN` is produced or compared                          |
| `Inf`          | `±Inf` is produced                                       |
| `Cancellation` | `a ± b` cancels most significant bits                    |
| `Swamping`     | an addend is too small to register                       |
| `Subnormal`    | a subnormal is produced                                  |
| `Rounding`     | `+ - * / sqrt` is inexact                                |

```julia
using MathChecker
x = checked(1e-8; cancellation=true)
(1 + x) - 1        # throws CancellationError
```

Disabled checks are eliminated by the compiler, so a `Checked{Float64}` with every flag
`false` is exactly as fast as a `Float64`.  See [`handler`](@ref) and
[`collect_failures`](@ref) for reporting failures without throwing.
"""
module MathChecker

using Printf: @sprintf
using Random: Random, AbstractRNG
using ScopedValues: ScopedValue, with

export Checked, checked, unchecked, flags, valuetype, DEFAULT_FLAGS
export CheckError,
    NaNError, InfError, SubnormalError, RoundingError, CancellationError, SwampingError
export bitslost
export with_handler, warn_handler, collect_failures

include("errors.jl")
include("handler.jl")
include("type.jl")
include("checkers.jl")
include("operations.jl")
include("show.jl")
include("random.jl")

# ---------------------------------------------------------------------------------------
# Error hint for Precision violations.  These surface as a `MethodError` for
# `mixed_precision(::PrecisionMismatch{X,Y}, x)`; explain what happened and how to fix it.
# (Built as one string and printed once, like the CheckError messages.)

function _precision_hint(io::IO, exc::MethodError, argtypes, kwargs)
    exc.f === mixed_precision || return nothing
    length(argtypes) >= 1 || return nothing
    M = argtypes[1]
    M <: PrecisionMismatch || return nothing
    X, Y = M.parameters
    # Blame the side that has the Precision check and does not permit the other.
    if !(X <: Checked && !permits(X, valuetype(Y)))
        X, Y = Y, X
    end
    T = valuetype(X)
    V = valuetype(Y)
    print(
        io,
        """


        MathChecker: the type $X
          has the `Precision` check enabled, which forbids implicitly mixing it with $Y.
          This usually means a `$T` computation was contaminated by a `$V` (a literal like
          `0.5`, or a value from another part of the code).  If the mixing is intentional,
          convert explicitly (e.g. `$T(x)` or `Checked{$T}(x)`), permit the type by setting
          the `Precision` flag to `$V` instead of `true` (`checked(x; precision=$V)`), or
          turn the check off.""",
    )
    return nothing
end

function __init__()
    # `register_error_hint` is experimental; guard the registration as its docstring
    # recommends, so that a future change to the API cannot break loading this package.
    if isdefined(Base.Experimental, :register_error_hint)
        Base.Experimental.register_error_hint(_precision_hint, MethodError)
    end
    return nothing
end

end
