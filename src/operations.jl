# Base methods for `Checked`.
#
# Every function here is treated as a *primitive*: it is evaluated on the unwrapped values
# with the ordinary `T` method, and only the final result is checked.  This means that a
# `hypot` or `sinpi` does not report the cancellation or absorption that happens inside
# Base's implementation — only the user's own arithmetic is checked.
#
# Methods are written for a concrete `X<:Checked` so that a single definition covers every
# combination of flags; binary methods take two values of the *same* `X`, and mixed-type
# calls (with a plain T, an Integer, a differently-flagged Checked, …) reach them through
# promotion.

# Wrap a result, running the checks first.
@inline function _wrap(::Type{X}, op, r, args...) where {X<:Checked}
    runchecks(X, op, r, args...)
    return X(r)
end
# Check a result without wrapping (for functions that return Bool/Int/etc.).
@inline function _bare(::Type{X}, op, r, args...) where {X<:Checked}
    runchecks(X, op, r, args...)
    return r
end

# ---------------------------------------------------------------------------------------
# Unary functions returning a value of type T

const _UNARY = (
    :-,
    :abs,
    :abs2,
    :sign,
    :inv,
    :sqrt,
    :cbrt,
    :exp,
    :exp2,
    :exp10,
    :expm1,
    :log,
    :log2,
    :log10,
    :log1p,
    :sin,
    :cos,
    :tan,
    :sec,
    :csc,
    :cot,
    :asin,
    :acos,
    :atan,
    :asec,
    :acsc,
    :acot,
    :sinh,
    :cosh,
    :tanh,
    :sech,
    :csch,
    :coth,
    :asinh,
    :acosh,
    :atanh,
    :asech,
    :acsch,
    :acoth,
    :sinpi,
    :cospi,
    :sind,
    :cosd,
    :tand,
    :asind,
    :acosd,
    :atand,
    :deg2rad,
    :rad2deg,
    :mod2pi,
    :significand,
    :nextfloat,
    :prevfloat,
    :eps,
)
for f in _UNARY
    @eval @inline Base.$f(a::X) where {X<:Checked} = _wrap(X, $f, $f(a.val), a.val)
end
@static if isdefined(Base, :tanpi)
    @inline Base.tanpi(a::X) where {X<:Checked} = _wrap(X, tanpi, tanpi(a.val), a.val)
end

# Tuple-returning unary functions: each component is checked separately.
@inline function Base.sincos(a::X) where {X<:Checked}
    s, c = sincos(a.val)
    return _wrap(X, sin, s, a.val), _wrap(X, cos, c, a.val)
end
@inline function Base.sincospi(a::X) where {X<:Checked}
    s, c = sincospi(a.val)
    return _wrap(X, sinpi, s, a.val), _wrap(X, cospi, c, a.val)
end
@inline function Base.sincosd(a::X) where {X<:Checked}
    s, c = sincosd(a.val)
    return _wrap(X, sind, s, a.val), _wrap(X, cosd, c, a.val)
end
@inline function Base.modf(a::X) where {X<:Checked}
    fpart, ipart = modf(a.val)
    return _wrap(X, modf, fpart, a.val), _wrap(X, modf, ipart, a.val)
end
@inline function Base.frexp(a::X) where {X<:Checked}
    x, e = frexp(a.val)
    return _wrap(X, frexp, x, a.val), e
end

# Unary functions returning something other than T, or taking an extra integer
@inline Base.exponent(a::Checked) = exponent(a.val)
@inline Base.nextfloat(a::X, n::Integer) where {X<:Checked} =
    _wrap(X, nextfloat, nextfloat(a.val, n), a.val, n)
@inline Base.prevfloat(a::X, n::Integer) where {X<:Checked} =
    _wrap(X, prevfloat, prevfloat(a.val, n), a.val, n)
@inline Base.ldexp(a::X, n::Integer) where {X<:Checked} =
    _wrap(X, ldexp, ldexp(a.val, n), a.val, n)

# ---------------------------------------------------------------------------------------
# Binary functions on two Checked values of the same type

const _BINARY =
    (:+, :-, :*, :/, :^, :atan, :hypot, :log, :mod, :rem, :copysign, :flipsign, :min, :max)
for f in _BINARY
    @eval @inline Base.$f(a::X, b::X) where {X<:Checked} =
        _wrap(X, $f, $f(a.val, b.val), a.val, b.val)
end

# Base's `hypot(::Number, ::Number)` promotes and then calls its *generic* algorithm rather
# than `hypot(::T, ::T)`, so mixed calls must be routed through promotion explicitly to
# get the same answer as the wrapped type.
@inline Base.hypot(a::Checked, b::Real) = hypot(promote(a, b)...)
@inline Base.hypot(a::Real, b::Checked) = hypot(promote(a, b)...)
@inline Base.hypot(a::Checked, b::Checked) = hypot(promote(a, b)...)
# Base's generic `copysign(::Real, ::Real)` and `flipsign(::Real, ::Real)` never promote,
# so mixed calls would bypass the checks (a NaN sign operand would be consumed silently).
for f in (:copysign, :flipsign)
    @eval begin
        @inline Base.$f(a::Checked, b::Real) = $f(promote(a, b)...)
        @inline Base.$f(a::Real, b::Checked) = $f(promote(a, b)...)
        # (Exact counterparts of Base's concrete `(Float64, Real)`, `(Float32, Real)`, and
        # `(Signed, Real)` methods, which would otherwise be ambiguous with `(Real, Checked)`.)
        @inline Base.$f(a::Float64, b::Checked) = $f(promote(a, b)...)
        @inline Base.$f(a::Float32, b::Checked) = $f(promote(a, b)...)
        @inline Base.$f(a::Signed, b::Checked) = $f(promote(a, b)...)
        @inline Base.$f(a::Rational, b::Checked) = $f(promote(a, b)...)   # vs Base's (Rational, Real)
        @inline Base.$f(a::Checked, b::Checked) = $f(promote(a, b)...)
    end
end

@inline function Base.minmax(a::X, b::X) where {X<:Checked}
    lo, hi = minmax(a.val, b.val)
    return _wrap(X, min, lo, a.val, b.val), _wrap(X, max, hi, a.val, b.val)
end

# Integer powers, including `x^2` via literal_pow.  (Base's `^(::Number, ::Integer)`
# falls back to `power_by_squaring`, which throws for negative exponents.)
@inline Base.:^(a::X, n::Integer) where {X<:Checked} = _wrap(X, ^, a.val^n, a.val, n)
@inline function Base.literal_pow(::typeof(^), a::X, ::Val{p}) where {X<:Checked,p}
    return _wrap(X, ^, Base.literal_pow(^, a.val, Val(p)), a.val, p)
end
# Base has a specific `literal_pow(^, ::AbstractFloat, ::Val{-1})`; disambiguate.
@inline function Base.literal_pow(::typeof(^), a::X, ::Val{-1}) where {X<:Checked}
    return _wrap(X, ^, Base.literal_pow(^, a.val, Val(-1)), a.val, -1)
end

# Ternary
@inline Base.fma(a::X, b::X, c::X) where {X<:Checked} =
    _wrap(X, fma, fma(a.val, b.val, c.val), a.val, b.val, c.val)
@inline Base.muladd(a::X, b::X, c::X) where {X<:Checked} =
    _wrap(X, muladd, muladd(a.val, b.val, c.val), a.val, b.val, c.val)

# Division-type functions with rounding modes
@inline Base.div(a::X, b::X, r::RoundingMode) where {X<:Checked} =
    _wrap(X, div, div(a.val, b.val, r), a.val, b.val, r)
# (`rem` per mode, because Base's fallbacks `rem(x, y, ::RoundingMode{M})` are untyped.)
for M in (:Nearest, :ToZero, :Up, :Down, :FromZero)
    @eval @inline Base.rem(
        a::X,
        b::X,
        r::RoundingMode{$(QuoteNode(M))},
    ) where {X<:Checked} = _wrap(X, rem, rem(a.val, b.val, r), a.val, b.val, r)
end
@inline Base.rem2pi(a::X, r::RoundingMode) where {X<:Checked} =
    _wrap(X, rem2pi, rem2pi(a.val, r), a.val, r)

# ---------------------------------------------------------------------------------------
# Rounding.  One method per RoundingMode, to avoid ambiguities with Base's per-mode
# methods for AbstractFloat.  Keyword arguments (digits, sigdigits, base) are forwarded.

for M in (:Nearest, :ToZero, :Up, :Down, :FromZero, :NearestTiesAway, :NearestTiesUp)
    @eval @inline function Base.round(
        a::X,
        r::RoundingMode{$(QuoteNode(M))};
        kwargs...,
    ) where {X<:Checked}
        return _wrap(X, round, round(a.val, r; kwargs...), a.val, r)
    end
end
# Rounding to an integer type is not checked (a NaN/Inf already throws InexactError).
Base.round(::Type{I}, a::Checked, r::RoundingMode) where {I<:Integer} = round(I, a.val, r)
Base.round(::Type{I}, a::Checked) where {I<:Integer} = round(I, a.val)
Base.trunc(::Type{I}, a::Checked) where {I<:Integer} = trunc(I, a.val)
Base.floor(::Type{I}, a::Checked) where {I<:Integer} = floor(I, a.val)
Base.ceil(::Type{I}, a::Checked) where {I<:Integer} = ceil(I, a.val)
Base.unsafe_trunc(::Type{I}, a::Checked) where {I<:Integer} = unsafe_trunc(I, a.val)
# (Base has `round(::Type{Bool}, ::AbstractFloat)` etc.; disambiguate.)
for f in (:round, :trunc, :floor, :ceil)
    @eval Base.$f(::Type{Bool}, a::Checked) = $f(Bool, a.val)
end

# ---------------------------------------------------------------------------------------
# Comparisons.  `==`, `isequal`, and `isless` are the "total order" family used by
# hashing and sorting and are never checked; `<`, `<=`, and `cmp` signal on NaN operands
# under the NaN check.  (`>` and `>=` are defined by Base in terms of `<` and `<=`.)

@inline Base.:(==)(a::X, b::X) where {X<:Checked} = a.val == b.val
@inline Base.isequal(a::X, b::X) where {X<:Checked} = isequal(a.val, b.val)
@inline Base.isless(a::X, b::X) where {X<:Checked} = isless(a.val, b.val)
@inline Base.:<(a::X, b::X) where {X<:Checked} = _bare(X, <, a.val < b.val, a.val, b.val)
@inline Base.:<=(a::X, b::X) where {X<:Checked} = _bare(X, <=, a.val <= b.val, a.val, b.val)
@inline Base.cmp(a::X, b::X) where {X<:Checked} =
    _bare(X, cmp, cmp(a.val, b.val), a.val, b.val)
# Base's mixed-type `isless` fallbacks are written in terms of `<`, which is checked; route
# them through promotion to the unchecked same-type method instead, so that sorting mixed
# collections works.  (`cmp`'s fallback is written in terms of `isless`; keep it checked.)
# Restricted to Base's number types, like `isapprox`, to avoid ambiguities with packages
# that define their own mixed `isless(::Foo, ::AbstractFloat)`.
const BaseReal = Union{BaseFloat,Integer,Rational,AbstractIrrational}
@inline Base.isless(a::Checked, b::Checked) = isless(promote(a, b)...)
@inline Base.isless(a::Checked, b::BaseReal) = isless(promote(a, b)...)
@inline Base.isless(a::BaseReal, b::Checked) = isless(promote(a, b)...)
@inline Base.cmp(a::Checked, b::Checked) = cmp(promote(a, b)...)
@inline Base.cmp(a::Checked, b::BaseReal) = cmp(promote(a, b)...)
@inline Base.cmp(a::BaseReal, b::Checked) = cmp(promote(a, b)...)
@inline Base.cmp(a::Checked, b::Rational) = cmp(promote(a, b)...)   # vs Base's (AbstractFloat, Rational)
@inline Base.cmp(a::Rational, b::Checked) = cmp(promote(a, b)...)
Base.hash(a::Checked, h::UInt) = hash(a.val, h)

# `isapprox` is a comparison, not arithmetic: evaluate it on the raw values so that the
# `x - y` inside it does not trigger the Cancellation check.
Base.isapprox(a::X, b::X; kwargs...) where {X<:Checked} = isapprox(a.val, b.val; kwargs...)
Base.isapprox(a::Checked, b::Checked; kwargs...) = isapprox(promote(a, b)...; kwargs...)
# (Mixed methods are restricted to Base's number types to avoid ambiguities with packages
# that define `isapprox(::Foo, ::Real)`; other mixes fall back to Base's generic method,
# which computes `x - y` with the checks active.)
Base.isapprox(a::Checked, b::BaseReal; kwargs...) = isapprox(promote(a, b)...; kwargs...)
Base.isapprox(a::BaseReal, b::Checked; kwargs...) = isapprox(promote(a, b)...; kwargs...)
Base.rtoldefault(::Type{X}) where {X<:Checked} = Base.rtoldefault(valuetype(X))

# ---------------------------------------------------------------------------------------
# Predicates: never checked (they are how one *inspects* a value).

for f in (:isnan, :isinf, :isfinite, :iszero, :isone, :signbit, :isinteger, :iseven, :isodd)
    @eval @inline Base.$f(a::Checked) = $f(a.val)
end
Base.issubnormal(a::Checked) = issubnormal(a.val)

# ---------------------------------------------------------------------------------------
# Type-level properties and special values (never checked)

for f in (:zero, :one, :typemin, :typemax, :floatmin, :floatmax, :maxintfloat, :eps)
    @eval Base.$f(::Type{X}) where {X<:Checked} = X($f(valuetype(X)))
end
Base.precision(::Type{X}; kwargs...) where {X<:Checked} = precision(valuetype(X); kwargs...)
Base.precision(a::Checked; kwargs...) = precision(a.val; kwargs...)
Base.decompose(a::Checked) = Base.decompose(a.val)
Base.bitstring(a::Checked) = bitstring(a.val)
Base.uinttype(::Type{X}) where {X<:Checked} = Base.uinttype(valuetype(X))
Base.exponent_bits(::Type{X}) where {X<:Checked} = Base.exponent_bits(valuetype(X))
Base.significand_bits(::Type{X}) where {X<:Checked} = Base.significand_bits(valuetype(X))
