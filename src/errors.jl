"""
    CheckError <: Exception

Supertype of the exceptions signalled by the runtime checks.  Every subtype has at least
the fields

- `op`: the function that was being evaluated (e.g. `+`, `sqrt`),
- `result`: the (unwrapped) value the operation produced, and
- `args::Tuple`: the (unwrapped) operands.

The concrete subtypes are [`NaNError`](@ref), [`InfError`](@ref),
[`SubnormalError`](@ref), [`RoundingError`](@ref), [`CancellationError`](@ref), and
[`SwampingError`](@ref).
"""
abstract type CheckError <: Exception end

"""
    NaNError(op, result, args)

Signalled by the `NaN` check when `op(args...)` produced a `NaN`, or when an ordering
comparison was attempted with a `NaN` operand.
"""
struct NaNError <: CheckError
    op::Any
    result::Any
    args::Tuple
end

"""
    InfError(op, result, args)

Signalled by the `Inf` check when `op(args...)` produced `±Inf`.
"""
struct InfError <: CheckError
    op::Any
    result::Any
    args::Tuple
end

"""
    SubnormalError(op, result, args)

Signalled by the `Subnormal` check when `op(args...)` produced a subnormal number.
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
    SwampingError(op, result, args, swamped, ratio, tolerance)

Signalled by the `Swamping` check when an operand of an addition or subtraction was too
small to (fully) register in the result.  `swamped` is the index into `args` of the
operand that was lost, `ratio` is the measured `|small| / |large|` of the two addends, and
`tolerance` is the relative threshold used, or `nothing` for the exact test.
"""
struct SwampingError <: CheckError
    op::Any
    result::Any
    args::Tuple
    swamped::Int
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

# Diagnostic numbers (ratios, tolerances, bit counts) are rounded to three significant
# figures for readability.
_short(x::AbstractFloat) = replace(repr(round(Float64(x); sigdigits = 3)), r"\.0$" => "")
_short(x) = repr(x)
_bits(x) = _short(-log2(Float64(x)))

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
    what = err.result isa Bool ? "compared a NaN" : "produced NaN"
    return ["$(_header(err)) $what."]
end

_lines(err::InfError) = ["$(_header(err)) produced $(_repr(err.result))."]

function _lines(err::SubnormalError)
    r = err.result
    T = typeof(r)
    first = "$(_header(err)) produced the subnormal number $(_repr(r)),"
    if T <: AbstractFloat
        fm = floatmin(T)
        return [
            first,
            "which is $(_short(fm / abs(r)))× smaller than the smallest normal $T (floatmin = $(_short(fm))).",
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

function _lines(err::SwampingError)
    T = typeof(err.result)
    first = "$(_header(err)) produced $(_repr(err.result)); the operand $(_repr(err.args[err.swamped])) was swamped:"
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
