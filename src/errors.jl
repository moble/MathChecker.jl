"""
    CheckError <: Exception

Supertype of the exceptions signalled by the runtime checks.  Every subtype has at least
the fields

- `op`: the function that was being evaluated (e.g. `+`, `sqrt`),
- `result`: the (unwrapped) value the operation produced, and
- `args::Tuple`: the (unwrapped) operands.

The concrete subtypes are [`NaNError`](@ref), [`InfError`](@ref),
[`SubnormalError`](@ref), [`RoundingError`](@ref), [`CancellationError`](@ref), and
[`AbsorptionError`](@ref).
"""
abstract type CheckError <: Exception end

"""
    NaNError(op, result, args)

Signalled by the `NaN` check when `op(args...)` produced a `NaN`, or had a `NaN` operand.
The message says whether the operation *generated* the `NaN` (no operand was `NaN`),
*propagated* it (`NaN` in, `NaN` out), or *consumed* it (`NaN` in, ordinary value out —
the point at which a `NaN` silently becomes a wrong answer).
"""
struct NaNError <: CheckError
    op::Any
    result::Any
    args::Tuple
end

"""
    InfError(op, result, args)

Signalled by the `Inf` check when `op(args...)` produced `±Inf`.  The message says whether
this was a division by zero (an exact infinity), an overflow, or the propagation of an
already-infinite operand.
"""
struct InfError <: CheckError
    op::Any
    result::Any
    args::Tuple
end

"""
    SubnormalError(op, result, args)

Signalled by the `Subnormal` check when `op(args...)` produced a subnormal number, or
underflowed to zero although its exact result is nonzero.
"""
struct SubnormalError <: CheckError
    op::Any
    result::Any
    args::Tuple
end

"""
    RoundingError(op, result, args, residual)

Signalled by the `Rounding` check when `op(args...)` was not exact.  `residual` is the
(approximate) rounding error `exact - result`, as computed by an error-free
transformation.
"""
struct RoundingError <: CheckError
    op::Any
    result::Any
    args::Tuple
    residual::Any
end

"""
    CancellationError(op, result, args, ratio, tolerance)

Signalled by the `Cancellation` check when an addition or subtraction lost most of its
significant bits.  `ratio` is the measured `|result| / max(|a|, |b|)` and `tolerance` the
relative threshold it fell below.  The number of bits lost is available from
[`bitslost`](@ref).
"""
struct CancellationError <: CheckError
    op::Any
    result::Any
    args::Tuple
    ratio::Any
    tolerance::Any
end

"""
    AbsorptionError(op, result, args, absorbed, ratio, tolerance)

Signalled by the `Absorption` check when an operand of an addition or subtraction was too
small to (fully) register in the result ("absorption", also called "swamping").
`absorbed` is the index into `args` of the
operand that was lost, `ratio` is the measured `|small| / |large|` of the two addends, and
`tolerance` is the relative threshold used, or `nothing` for the exact test.
"""
struct AbsorptionError <: CheckError
    op::Any
    result::Any
    args::Tuple
    absorbed::Int
    ratio::Any
    tolerance::Any
end

"""
    bitslost(err::CancellationError)

The number of significant bits cancelled: `log2(max(|a|, |b|) / |a ± b|)`, or `Inf` if the
result was exactly zero.
"""
function bitslost(err::CancellationError)
    return iszero(err.ratio) ? oftype(float(err.ratio), Inf) : -log2(err.ratio)
end


# ---------------------------------------------------------------------------------------
# Pretty-printing
#
# Each error's message is built as a single string and written with one `print`, so that
# it cannot interleave with other output.  Long messages are broken into lines; the
# continuation lines are indented by the width of the REPL's "ERROR: " prefix so that they
# line up under the error name.

const _INFIX_OPS = (:+, :-, :*, :/, :^, :<, :<=, :>, :>=, :(==))
const _INDENT = " "^7

_opname(op) = op isa Function ? string(nameof(op)) : string(op)

# The operands and result are always shown in full, exactly as `show` would print them.
_repr(x) = repr(x)
_repr(::RoundingMode{M}) where {M} = "Round$M"

# Diagnostic numbers (ratios, tolerances, bit counts) are shown to three significant
# figures for readability.
_short(x::AbstractFloat) = @sprintf("%.3g", Float64(x))
_short(x) = repr(x)
_bits(x) = _short(-log2(Float64(x)))
# A "how many times smaller/larger" factor: an integer when it is a modest one.
_factor(x) = 1 <= x < 1e6 ? string(round(Int, x)) : _short(x)

"""
    MathChecker.formatcall(op, args) -> String

The call `op(args...)` in a readable form: infix for binary operators (`"a + b"`),
functional otherwise (`"sqrt(a)"`).
"""
function formatcall(op, args::Tuple)
    name = _opname(op)
    if length(args) == 2 && Symbol(name) in _INFIX_OPS
        return "$(_repr(args[1])) $name $(_repr(args[2]))"
    elseif length(args) == 1 && Symbol(name) == :-
        return "-($(_repr(args[1])))"
    else
        return "$name($(join(map(_repr, args), ", ")))"
    end
end

"""
    MathChecker.message(err::CheckError) -> String

The full text of the error message, as printed by `showerror`.  Continuation lines are
indented to line up under the error name after the REPL's `ERROR: ` prefix.
"""
message(err::CheckError) = join(_lines(err), "\n" * _INDENT)

Base.showerror(io::IO, err::CheckError) = print(io, message(err))

_header(err::CheckError) = "$(nameof(typeof(err))): $(formatcall(err.op, err.args))"

function _lines(err::NaNError)
    r = err.result
    nan_in = any(x -> x isa Number && isnan(x), err.args)
    nan_out = r isa Number && isnan(r)
    if nan_out && !nan_in
        return ["$(_header(err)) produced NaN (no operand was NaN)."]
    elseif nan_out
        return ["$(_header(err)) produced NaN, propagating the NaN operand."]
    else
        return [
            "$(_header(err)) produced $(_repr(r)), consuming the NaN operand:",
            "the NaN is silently lost here.",
        ]
    end
end

# Distinguish the IEEE DIVBYZERO case (an exact infinity from finite operands) from OVERFLOW
# (a finite exact result too large to represent) and from propagation of an infinite operand.
function _infinity_reason(err::InfError)
    op, args, r = err.op, err.args, err.result
    nums = filter(x -> x isa Number, collect(args))
    if any(isinf, nums)
        return ["an operand was already infinite."]
    end
    exact =
        (op === (/) && length(args) == 2 && iszero(args[2])) ||
        (op === inv && length(args) == 1 && iszero(args[1])) ||
        (op in (log, log2, log10) && length(args) == 1 && iszero(args[1])) ||
        (op === log1p && length(args) == 1 && args[1] == -1) ||
        (
            op === (^) &&
            length(args) == 2 &&
            iszero(args[1]) &&
            args[2] isa Real &&
            args[2] < 0
        )
    exact && return ["division by zero (the exact result is infinite)."]
    T = typeof(r)
    if T <: AbstractFloat
        return [
            "overflow (the exact result is finite but exceeds floatmax($T) = $(_short(floatmax(T)))).",
        ]
    end
    return ["overflow."]
end

_lines(err::InfError) =
    ["$(_header(err)) produced $(_repr(err.result)):", _infinity_reason(err)...]

function _lines(err::SubnormalError)
    r = err.result
    T = typeof(r)
    if iszero(r)
        tiny = T <: AbstractFloat ? " (≈ $(_short(nextfloat(zero(T)))))" : ""
        return [
            "$(_header(err)) produced $(_repr(r)), having underflowed:",
            "the exact result is nonzero but smaller than the smallest positive $T$tiny.",
        ]
    end
    first = "$(_header(err)) produced the subnormal number $(_repr(r)),"
    if T <: AbstractFloat
        fm = floatmin(T)
        return [
            first,
            "which is $(_factor(fm / abs(r)))× smaller than the smallest normal $T (floatmin = $(_short(fm))).",
        ]
    else
        return [first[1:(end-1)] * "."]
    end
end

function _lines(err::RoundingError)
    r = err.result
    ulps = if r isa AbstractFloat && isfinite(r)
        u = abs(err.residual) / eps(abs(r))
        " ($(_short(u)) ulp$(u == 1 ? "" : "s"))"
    else
        ""
    end
    return [
        "$(_header(err)) produced $(_repr(r)), which is inexact:",
        "exact − computed ≈ $(_repr(err.residual))$ulps.",
    ]
end

function _lines(err::CancellationError)
    lost = bitslost(err)
    T = typeof(err.result)
    nbits = isinf(lost) ? "all" : _short(lost)
    of = T <: AbstractFloat ? " of $(precision(T))" : ""
    return [
        "$(_header(err)) produced $(_repr(err.result)),",
        "cancelling $nbits$of significant bits: |result| / max(|a|, |b|) = $(_short(err.ratio))",
        "is below the tolerance $(_short(err.tolerance)) ($(_bits(err.tolerance)) bits).",
    ]
end

function _lines(err::AbsorptionError)
    T = typeof(err.result)
    first = "$(_header(err)) produced $(_repr(err.result)); the operand $(_repr(err.args[err.absorbed])) was absorbed:"
    ratio = "|small| / |large| = $(_short(err.ratio))"
    if err.tolerance === nothing
        lines = [first, "$ratio, so it made no difference to the result"]
        T <: AbstractFloat &&
            push!(lines, "(anything below ≈ $(_short(eps(T) / 2)) would be lost)")
        lines[end] *= "."
        return lines
    else
        return [first, "$ratio is below the tolerance $(_short(err.tolerance))."]
    end
end
