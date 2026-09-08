# The runtime check implementations.
#
# `runchecks(X, op, result, args...)` is called by every checked operation with the
# *unwrapped* result and operands.  The flags are type parameters of `X`, so each
# `flag && check_…(…)` below is a compile-time constant and disabled checks vanish.  The
# individual `check_…` functions dispatch on `typeof(op)` and fall through to a no-op for
# operations they do not apply to, which also compiles away.

"""
    MathChecker.runchecks(::Type{X<:Checked}, op, result, args...)

Run the checks enabled in the type `X` on `result = op(args...)` (all unwrapped).  The
`NaN`, `Inf`, and `Subnormal` checks run first, so that a non-finite result is reported as
such rather than as a cancellation or swamping.
"""
@inline function runchecks(
    ::Type{Checked{T,P,N,I,C,S,Sb,R}},
    op,
    result,
    args...,
) where {T,P,N,I,C,S,Sb,R}
    N && check_nan(op, result, args...)
    I && check_inf(op, result, args...)
    Sb && check_subnormal(op, result, args...)
    R && check_rounding(op, result, args...)
    C === false || check_cancellation(C, op, result, args...)
    S === false || check_swamping(S, op, result, args...)
    return nothing
end

# Operations with two "additive" operands, for the Cancellation and Swamping checks.
const AdditiveOp = Union{typeof(+),typeof(-)}

# ---------------------------------------------------------------------------------------
# NaN
#
# A NaN operand signals whether or not the result is NaN — the semantics of a signaling
# NaN.  This catches the three stages of a NaN's life: generation (`0/0`), propagation
# (`NaN + 1`), and, most importantly, the "kill", where an operation consumes a NaN and
# produces an ordinary value (`NaN < 1 → false`, `NaN^0 → 1`), silently turning a
# detectable problem into a wrong answer.  The total-order functions (`==`, `isequal`,
# `isless`) and the inspection predicates (`isnan`, …) bypass the checks entirely, so
# sorting, hashing, and testing for NaN keep working.

@inline _isnan(x::Number) = isnan(x)
@inline _isnan(x) = false
@inline _anynan() = false
@inline _anynan(a, rest...) = _isnan(a) | _anynan(rest...)

@inline function check_nan(op, r, args...)
    (_isnan(r) | _anynan(args...)) && fail(NaNError(op, r, args))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Inf

@inline function check_inf(op, r, args...)
    isinf(r) && fail(InfError(op, r, args))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Subnormal

"""
    MathChecker.issubnormal(x)

Like `Base.issubnormal`, but defined (as `false`) for any `Real`, so that the `Subnormal`
check can be used with types that do not implement `Base.issubnormal`.  Extend this for
such types if they can hold subnormal values.
"""
issubnormal(x::Base.IEEEFloat) = Base.issubnormal(x)
issubnormal(x::BigFloat) = false  # MPFR has no subnormals
issubnormal(x::Real) = false

@inline function check_subnormal(op, r, args...)
    issubnormal(r) && fail(SubnormalError(op, r, args))
    return nothing
end

# Underflow all the way to zero.  IEEE's UNDERFLOW flag covers results that are tiny *and*
# inexact; a zero result from an operation whose exact result cannot be zero is the extreme
# case, and is not subnormal, so it needs its own test.  Only operations for which "the
# exact result is nonzero" can be decided from the operands are covered.
const _UnderflowUnary = Union{
    typeof(exp),
    typeof(exp2),
    typeof(exp10),
    typeof(expm1),
    typeof(log1p),
    typeof(sqrt),
    typeof(cbrt),
    typeof(sin),
    typeof(tan),
    typeof(asin),
    typeof(atan),
    typeof(sinh),
    typeof(tanh),
    typeof(asinh),
    typeof(atanh),
}
@inline _nonzerofinite(x) = !iszero(x) && isfinite(x)
@inline function _underflowed(op, r, args, exactnonzero::Bool)
    if issubnormal(r) || (iszero(r) && exactnonzero)
        fail(SubnormalError(op, r, args))
    end
    return nothing
end
@inline check_subnormal(op::typeof(exp), r, a) = _underflowed(op, r, (a,), isfinite(a))
@inline check_subnormal(op::typeof(exp2), r, a) = _underflowed(op, r, (a,), isfinite(a))
@inline check_subnormal(op::typeof(exp10), r, a) = _underflowed(op, r, (a,), isfinite(a))
@inline check_subnormal(op::_UnderflowUnary, r, a) =
    _underflowed(op, r, (a,), _nonzerofinite(a))
@inline function check_subnormal(op::Union{typeof(*),typeof(/)}, r, a, b)
    return _underflowed(op, r, (a, b), _nonzerofinite(a) && _nonzerofinite(b))
end
@inline check_subnormal(op::typeof(ldexp), r, a, n) =
    _underflowed(op, r, (a, n), _nonzerofinite(a))
@inline check_subnormal(op::typeof(^), r, a, b) =
    _underflowed(op, r, (a, b), _nonzerofinite(a) && isfinite(b))

# ---------------------------------------------------------------------------------------
# Rounding — error-free transformations

# Knuth's TwoSum; `r` must be `a + b` rounded to nearest.
@inline function _twosum_residual(r, a, b)
    v = r - a
    return (a - (r - v)) + (b - v)
end

@inline check_rounding(op, r, args...) = nothing
@inline function check_rounding(::typeof(+), r, a, b)
    if isfinite(r)
        e = _twosum_residual(r, a, b)
        iszero(e) || fail(RoundingError(+, r, (a, b), e))
    end
    return nothing
end
@inline function check_rounding(::typeof(-), r, a, b)
    if isfinite(r)
        e = _twosum_residual(r, a, -b)
        iszero(e) || fail(RoundingError(-, r, (a, b), e))
    end
    return nothing
end
@inline function check_rounding(::typeof(*), r, a, b)
    if isfinite(r)
        e = fma(a, b, -r)
        iszero(e) || fail(RoundingError(*, r, (a, b), e))
    end
    return nothing
end
@inline function check_rounding(::typeof(/), r, a, b)
    if isfinite(r) && !iszero(b)
        e = fma(-r, b, a)  # a - r*b, exactly; nonzero iff the quotient was rounded
        iszero(e) || fail(RoundingError(/, r, (a, b), e / b))
    end
    return nothing
end
@inline function check_rounding(::typeof(sqrt), r, a)
    if isfinite(r) && !iszero(r)
        e = fma(-r, r, a)  # a - r^2, exactly
        iszero(e) || fail(RoundingError(sqrt, r, (a,), e / (2r)))
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Cancellation.  `tol` is `true` (default tolerance) or a Float64.

@inline _tolerance(::Bool, ::Type{T}) where {T} = sqrt(eps(T))
@inline _tolerance(tol::Float64, ::Type{T}) where {T} = T(tol)

@inline function _cancellation(tol, op, r, a, b, args)
    if isfinite(r)
        m = max(abs(a), abs(b))
        t = _tolerance(tol, typeof(r))
        if !iszero(m) && abs(r) < t * m
            fail(CancellationError(op, r, args, abs(r) / m, t))
        end
    end
    return nothing
end

@inline check_cancellation(tol, op, r, args...) = nothing
@inline check_cancellation(tol, op::AdditiveOp, r, a, b) =
    _cancellation(tol, op, r, a, b, (a, b))
# fma(a, b, c) and muladd(a, b, c): the additive step is (a*b) + c.
@inline function check_cancellation(tol, op::Union{typeof(fma),typeof(muladd)}, r, a, b, c)
    return _cancellation(tol, op, r, a * b, c, (a, b, c))
end

# ---------------------------------------------------------------------------------------
# Swamping.  `tol` is `true` (exact test) or a Float64.

# `x` and `y` are the two addends (already sign-adjusted so that r ≈ x + y); `ix` and
# `iy` are their positions in the reported `args`.
@inline function _swamping(tol::Bool, op, r, x, y, ix, iy, args)
    if isfinite(r)
        if r == x && !iszero(y)
            fail(SwampingError(op, r, args, iy, abs(y) / abs(x), nothing))
        elseif r == y && !iszero(x)
            fail(SwampingError(op, r, args, ix, abs(x) / abs(y), nothing))
        end
    end
    return nothing
end
@inline function _swamping(tol::Float64, op, r, x, y, ix, iy, args)
    if isfinite(r)
        t = _tolerance(tol, typeof(r))
        ax, ay = abs(x), abs(y)
        if !iszero(y) && ay < t * ax
            fail(SwampingError(op, r, args, iy, ay / ax, t))
        elseif !iszero(x) && ax < t * ay
            fail(SwampingError(op, r, args, ix, ax / ay, t))
        end
    end
    return nothing
end

@inline check_swamping(tol, op, r, args...) = nothing
@inline check_swamping(tol, ::typeof(+), r, a, b) = _swamping(tol, +, r, a, b, 1, 2, (a, b))
@inline check_swamping(tol, ::typeof(-), r, a, b) =
    _swamping(tol, -, r, a, -b, 1, 2, (a, b))
@inline function check_swamping(tol, op::Union{typeof(fma),typeof(muladd)}, r, a, b, c)
    return _swamping(tol, op, r, a * b, c, 1, 3, (a, b, c))
end
