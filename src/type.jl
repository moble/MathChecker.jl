"""
    Checked{T<:AbstractFloat, Precision, NaN, Inf, Cancellation, Absorption, Subnormal, Rounding} <: AbstractFloat

A floating-point number of type `T` whose every operation is verified by the checks
selected by the flag type parameters.  A `Checked` participates in arithmetic exactly like
a `T` — all of `Base`'s arithmetic, math, comparison, rounding, and conversion functions
are supported — but after every operation the enabled checks inspect the result (and
operands) and signal a [`CheckError`](@ref) through the current [`handler`](@ref) if
something is wrong.  Disabled checks cost nothing: they are eliminated at compile time.

# Flags

Each flag is `false` (off) or `true` (on).  Three of them accept a configuration value in
place of `true`:

| Flag           | Signals when …                                       | Instead of `true` …                    |
|:---------------|:-----------------------------------------------------|:---------------------------------------|
| `Precision`    | implicitly mixed with a float of another type        | a `Type` of extra permitted types      |
| `NaN`          | a `NaN` is produced, or used as an operand           |                                        |
| `Inf`          | `±Inf` is produced                                   |                                        |
| `Cancellation` | `a ± b` loses more than half its significant bits    | a `Float64` relative tolerance         |
| `Absorption`     | an addend is too small to change the result at all   | a `Float64` relative tolerance         |
| `Subnormal`    | a subnormal number is produced                       |                                        |
| `Rounding`     | `+`, `-`, `*`, `/`, or `sqrt` is not exact           |                                        |

Each flag is documented in detail in the manual's "Checks" section.  The defaults, used by
`Checked{T}(x)` and [`checked`](@ref), turn on `Precision`, `NaN`, and `Inf` — the three
checks that can never produce a false positive — and leave the rest off.

# Constructors

    Checked{T, flags...}(x)                 # x::Real; converts x to T; never signals
    Checked{T}(x; nan=true, inf=true, …)    # defaults for flags not given
    Checked(x; …)                           # T = typeof(float(x))
    checked(x; …)                           # also handles arrays, tuples, complexes

Constructors never signal, even for `NaN` or `Inf`, so that sentinels can be created (see
the `NaN` check).  Constructors are also exempt from the `Precision` check: they are
*explicit* conversions.  The functions [`checked`](@ref) and [`unchecked`](@ref) wrap and
unwrap values, arrays, tuples, and complex numbers; [`flags`](@ref) and
[`valuetype`](@ref) recover the parameters.

# Examples

```jldoctest
julia> x = Checked(1.0)
Checked{Float64}(1.0)

julia> x / 0
ERROR: InfError: 1.0 / 0.0 produced Inf:
       division by zero (the exact result is infinite).
[...]

julia> unchecked(sqrt(x + 1))
1.4142135623730951

julia> y = checked(1e-9; cancellation=true)
Checked{Float64, true, true, true, true, false, false, false}(1.0e-9)

julia> (1 + y) - 1
ERROR: CancellationError: 1.000000001 - 1.0 produced 1.000000082740371e-9,
       cancelling 29.9 of 53 significant bits: |result| / max(|a|, |b|) = 1e-09
       is below the tolerance 1.49e-08 (26 bits).
[...]
```

# Promotion

Two `Checked` values with the same `T` promote to a `Checked` with the *union* of their
flags, so a value checked for `NaN` added to a value checked for `Inf` is checked for
both.  A `Checked{T}` combined with a plain `T`, `Integer`, `Rational`, or irrational
constant yields a `Checked{T}`.  Combining with a *different* floating-point type follows
Julia's usual promotion unless the `Precision` flag is set, in which case the checked
value keeps its own `T` and the conversion of the other operand is a `MethodError` (with
an explanatory hint) unless that type is permitted.
"""
struct Checked{T<:AbstractFloat,P,N,I,C,S,Sb,R} <: AbstractFloat
    val::T
    function Checked{T,P,N,I,C,S,Sb,R}(x::T) where {T<:AbstractFloat,P,N,I,C,S,Sb,R}
        T <: Checked && throw(ArgumentError("Checked types cannot be nested: $T"))
        _validflags(P, N, I, C, S, Sb, R) || throw(
            ArgumentError(
                "invalid Checked flags $((P, N, I, C, S, Sb, R)): each must be `false` or " *
                "`true`; `Precision` may also be a `Type`, and `Cancellation` and `Absorption` " *
                "may also be a `Float64` tolerance",
            ),
        )
        return new{T,P,N,I,C,S,Sb,R}(x)
    end
end

const _FLAG_NAMES =
    (:precision, :nan, :inf, :cancellation, :absorption, :subnormal, :rounding)

"""
    DEFAULT_FLAGS

The flags used when none are specified: `Precision`, `NaN`, and `Inf` on; everything else
off.

```julia
(precision = true, nan = true, inf = true, cancellation = false, absorption = false,
 subnormal = false, rounding = false)
```
"""
const DEFAULT_FLAGS = (
    precision = true,
    nan = true,
    inf = true,
    cancellation = false,
    absorption = false,
    subnormal = false,
    rounding = false,
)

_isflag(x) = x isa Bool
_isprecision(x) = x isa Bool || x isa Type
_istolerance(x) = x isa Bool || (x isa Float64 && x > 0)
function _validflags(P, N, I, C, S, Sb, R)
    return _isprecision(P) &&
           _isflag(N) &&
           _isflag(I) &&
           _istolerance(C) &&
           _istolerance(S) &&
           _isflag(Sb) &&
           _isflag(R)
end

"""
    flags(x::Checked)
    flags(::Type{<:Checked})

The check flags of `x` as a `NamedTuple` with fields `precision`, `nan`, `inf`,
`cancellation`, `absorption`, `subnormal`, and `rounding`, in that order (the order of the
type parameters).
"""
function flags(::Type{Checked{T,P,N,I,C,S,Sb,R}}) where {T,P,N,I,C,S,Sb,R}
    return (
        precision = P,
        nan = N,
        inf = I,
        cancellation = C,
        absorption = S,
        subnormal = Sb,
        rounding = R,
    )
end
flags(x::Checked) = flags(typeof(x))

"""
    valuetype(x::Checked)
    valuetype(::Type{<:Checked})

The underlying floating-point type `T` of a `Checked{T, …}`.  For any other type, the
type itself.
"""
valuetype(::Type{<:Checked{T}}) where {T} = T
valuetype(::Type{T}) where {T} = T
valuetype(x) = valuetype(typeof(x))

# Build the concrete type from a value type and a full flags NamedTuple.
@inline function _checkedtype(::Type{T}, f::NamedTuple) where {T}
    return Checked{
        T,
        f.precision,
        f.nan,
        f.inf,
        f.cancellation,
        f.absorption,
        f.subnormal,
        f.rounding,
    }
end

function _mergeflags(base::NamedTuple, kw::NamedTuple)
    for k in keys(kw)
        k in _FLAG_NAMES ||
            throw(ArgumentError("unknown check flag `$k`; valid flags are $(_FLAG_NAMES)"))
    end
    return merge(base, kw)
end
_kwtype(::Type{T}, base::NamedTuple, kw::NamedTuple) where {T} =
    _checkedtype(T, _mergeflags(base, kw))

# Explicit constructors: permissive (no Precision check), never signal.  A `Checked`
# argument is unwrapped first, so that `T`'s constructor never sees a `Checked`.
Checked{T,P,N,I,C,S,Sb,R}(x::Checked{T,P,N,I,C,S,Sb,R}) where {T,P,N,I,C,S,Sb,R} = x
function Checked{T,P,N,I,C,S,Sb,R}(x::Checked) where {T,P,N,I,C,S,Sb,R}
    T <: Checked && throw(ArgumentError("Checked types cannot be nested: $T"))
    return Checked{T,P,N,I,C,S,Sb,R}(T(x.val))
end
function Checked{T,P,N,I,C,S,Sb,R}(x::Real) where {T,P,N,I,C,S,Sb,R}
    T <: Checked && throw(ArgumentError("Checked types cannot be nested: $T"))
    return Checked{T,P,N,I,C,S,Sb,R}(T(x))
end
# (Rational separately, to avoid an ambiguity with Base's `(::Type{<:AbstractFloat})(::Rational{S})
# where S`; the unconstrained `S` must be matched exactly.)
function Checked{T,P,N,I,C,S,Sb,R}(x::Rational{Q}) where {Q,T,P,N,I,C,S,Sb,R}
    T <: Checked && throw(ArgumentError("Checked types cannot be nested: $T"))
    return Checked{T,P,N,I,C,S,Sb,R}(T(x))
end
Checked{T}(x::Real; kw...) where {T} = _kwtype(T, DEFAULT_FLAGS, values(kw))(x)
Checked{T}(x::Rational{Q}; kw...) where {Q,T} = _kwtype(T, DEFAULT_FLAGS, values(kw))(x)
Checked{T}(x::Checked; kw...) where {T} = _kwtype(T, flags(x), values(kw))(x)
Checked(x::Checked; kw...) = _kwtype(valuetype(x), flags(x), values(kw))(x)
Checked(x::AbstractFloat; kw...) = _kwtype(typeof(x), DEFAULT_FLAGS, values(kw))(x)
Checked(x::Real; kw...) = Checked(float(x); kw...)
Checked(x::Rational{Q}; kw...) where {Q} = Checked(float(x); kw...)

"""
    checked(x; precision=true, nan=true, inf=true, cancellation=false, absorption=false,
               subnormal=false, rounding=false)
    checked(T::Type{<:AbstractFloat}; flags...)

Wrap `x` in a [`Checked`](@ref) with the given check flags (see `Checked` for their
meanings and accepted values); flags not mentioned take their defaults.

`x` may be a real number, a `Complex`, a `Tuple`, or an `AbstractArray` of any of these;
containers are wrapped elementwise.  Integers and rationals are converted to `Float64`
first.  Applied to a `Checked` value, the flags given are *changed* and the others kept,
so `checked(x; cancellation=true)` adds a check to `x`.

Applied to a floating-point *type*, `checked` returns the corresponding `Checked` type,
which is convenient with `zeros`, `rand`, etc.:

```julia
zeros(checked(Float64; nan=true), 3)
```

See also [`unchecked`](@ref).
"""
checked(x::AbstractFloat; kw...) = Checked(x; kw...)
checked(x::Checked; kw...) = Checked(x; kw...)
checked(x::Real; kw...) = Checked(float(x); kw...)
checked(::Type{T}; kw...) where {T<:AbstractFloat} = _kwtype(T, DEFAULT_FLAGS, values(kw))
checked(::Type{X}; kw...) where {X<:Checked} = _kwtype(valuetype(X), flags(X), values(kw))
checked(z::Complex; kw...) = Complex(checked(real(z); kw...), checked(imag(z); kw...))
checked(t::Tuple; kw...) = map(x -> checked(x; kw...), t)
checked(A::AbstractArray; kw...) = map(x -> checked(x; kw...), A)

"""
    unchecked(x)

Remove the [`Checked`](@ref) wrapper from `x`, returning the underlying value.
`Complex`es, `Tuple`s, and `AbstractArray`s are unwrapped elementwise; anything else is
returned unchanged, so `unchecked` can be applied blindly to the result of a computation.

See also [`checked`](@ref).
"""
unchecked(x::Checked) = x.val
unchecked(x) = x
unchecked(z::Complex) = Complex(unchecked(real(z)), unchecked(imag(z)))
unchecked(t::Tuple) = map(unchecked, t)
unchecked(A::AbstractArray{<:Checked}) = map(unchecked, A)
unchecked(A::AbstractArray{<:Complex{<:Checked}}) = map(unchecked, A)
unchecked(A::AbstractArray) = A

# ---------------------------------------------------------------------------------------
# Precision: implicit conversion and promotion
#
# Semantics: a `Checked{T, P, …}` with `P !== false` *permits* a value type `V` if
# `V === T`, `V` is an exact type (Integer, Rational, AbstractIrrational), or `P` is a
# `Type` and `V <: P`.  An implicit conversion between two types is allowed only if each
# side that has the Precision check permits the other's value type; plain types and
# `Checked` types without the check permit everything.  In promotion, a precision-checked
# value keeps its own `T` ("absorbs" the other operand) rather than following Julia's
# usual widening, so that `Checked{Double64, Float64, …} * 0.5` stays a `Double64` and the
# type named in any error is the one the user actually wrote.

"""
    MathChecker.PrecisionMismatch{X, Y}

Trait type marking that values of types `X` and `Y` may not be implicitly converted into
one another, because at least one of them is a `Checked` with the `Precision` flag that
does not permit the other.  There is deliberately no method of
[`MathChecker.mixed_precision`](@ref) for this type, so that the attempt fails with a
`MethodError` (which carries an explanatory hint).
"""
struct PrecisionMismatch{X,Y} end

struct PrecisionOK end

"""
    MathChecker.hasprecision(::Type{<:Checked}) -> Bool

Whether the type's `Precision` flag is set (to `true` or to a whitelist type).
"""
hasprecision(::Type{<:Checked{T,P}}) where {T,P} = P !== false
hasprecision(::Type) = false

# Does the type `X` permit implicit mixing with values of type `V`?
@inline function permits(::Type{<:Checked{T,P}}, ::Type{V}) where {T,P,V}
    P === false && return true
    return V === T ||
           V <: Integer ||
           V <: Rational ||
           V <: AbstractIrrational ||
           (P isa Type && V <: P)
end
@inline permits(::Type, ::Type) = true

@inline function precision_trait(::Type{X}, ::Type{Y}) where {X,Y}
    ok = permits(X, valuetype(Y)) && permits(Y, valuetype(X))
    return ok ? PrecisionOK() : PrecisionMismatch{X,Y}()
end

"""
    MathChecker.mixed_precision(trait, x)

Identity on `x` when `trait` is `PrecisionOK()`.  Deliberately has **no method** for a
[`PrecisionMismatch`](@ref), so that implicitly mixing a `Checked` that has the
`Precision` flag with a float of another type is a `MethodError`.
"""
@inline mixed_precision(::PrecisionOK, x) = x

# Implicit conversions are strict.  (Note `convert(T, x::Number) = T(x)` in Base, so the
# constructors above would otherwise be used implicitly.)
Base.convert(::Type{X}, x::X) where {X<:Checked} = x
function Base.convert(::Type{X}, x::Y) where {X<:Checked,Y<:Checked}
    return X(mixed_precision(precision_trait(X, Y), x))
end
function Base.convert(::Type{X}, x::Real) where {X<:Checked}
    return X(mixed_precision(precision_trait(X, typeof(x)), x))
end
# (Restricted to Base's float types: a generic `S<:AbstractFloat` would be ambiguous with
# the `(::Type{Foo})(x::Real)` constructors that most third-party float types define.
# Conversion to such a type therefore goes through the type's own constructor, which is
# permissive.)
const BaseFloat = Union{Base.IEEEFloat,BigFloat}
function Base.convert(::Type{S}, x::X) where {S<:BaseFloat,X<:Checked}
    return S(mixed_precision(precision_trait(S, X), x.val))
end
Base.convert(::Type{AbstractFloat}, x::Checked) = x

# Promotion.  Flags are unioned; the value type follows Julia's rules unless a
# precision-checked operand is involved, in which case that operand's `T` is kept.
@inline _orflag(a::Bool, b::Bool) = a | b
@inline _orflag(a, b) = a === false ? b : b === false ? a : _mergeflag(a, b)
# Both flags set with different configurations: pick the stricter, symmetrically.
@inline _mergeflag(a::Type, b::Type) = Union{a,b}
@inline _mergeflag(a::Type, ::Bool) = true
@inline _mergeflag(::Bool, b::Type) = true
@inline _mergeflag(a::Float64, b::Float64) = max(a, b)
@inline _mergeflag(::Float64, ::Bool) = true
@inline _mergeflag(::Bool, ::Float64) = true
@inline _mergeflag(a, b) = a

@inline function _promote_value(::Type{X}, ::Type{Y}) where {X<:Checked,Y<:Checked}
    T, S = valuetype(X), valuetype(Y)
    T === S && return T
    px, py = hasprecision(X), hasprecision(Y)
    px && !py && return T
    py && !px && return S
    return promote_type(T, S)
end
function Base.promote_rule(::Type{X}, ::Type{Y}) where {X<:Checked,Y<:Checked}
    return _checkedtype(_promote_value(X, Y), map(_orflag, flags(X), flags(Y)))
end
function Base.promote_rule(::Type{X}, ::Type{S}) where {X<:Checked,S<:Real}
    T = valuetype(X)
    return _checkedtype(hasprecision(X) ? T : promote_type(T, S), flags(X))
end
# Irrationals adopt the precision of the Checked value (as they do for Float32/Float16);
# this overrides Base's rule, which would go through Float64.
Base.promote_rule(::Type{X}, ::Type{<:AbstractIrrational}) where {X<:Checked} = X
Base.promote_rule(::Type{<:AbstractIrrational}, ::Type{X}) where {X<:Checked} = X
# Base's rule `promote_rule(BigFloat, <:AbstractFloat) = BigFloat` disagrees with ours;
# both directions must agree or `promote_type` recurses forever.
Base.promote_rule(::Type{BigFloat}, ::Type{X}) where {X<:Checked} =
    promote_rule(X, BigFloat)
# Likewise `promote_rule(BigInt, <:AbstractFloat) = BigFloat`.
Base.promote_rule(::Type{BigInt}, ::Type{X}) where {X<:Checked} = promote_rule(X, BigInt)

# Explicit conversions out of the wrapper are permissive.
(::Type{S})(x::Checked) where {S<:BaseFloat} = S(x.val)
(::Type{S})(x::Checked) where {S<:Integer} = S(x.val)
Base.Bool(x::Checked) = Bool(x.val)
Base.Rational{I}(x::Checked) where {I<:Integer} = Rational{I}(x.val)
Base.Rational{BigInt}(x::Checked) = Rational{BigInt}(x.val)   # (Base has a BigInt-specific method)
Base.Rational(x::Checked) = Rational(x.val)
Base.AbstractFloat(x::Checked) = x
Base.float(x::Checked) = x
Base.float(::Type{X}) where {X<:Checked} = X
Base.big(x::X) where {X<:Checked} = _checkedtype(BigFloat, flags(X))(big(x.val))
Base.widen(::Type{X}) where {X<:Checked} = _checkedtype(widen(valuetype(X)), flags(X))
