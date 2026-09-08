# A Checked value, when nothing goes wrong, must behave *exactly* like the value it wraps.
# These tests compare every supported operation on a Checked against the same operation
# on the raw value, across all float types.

@testitem "unary functions match the wrapped type" tags=[:unit, :validation, :fast] setup=[
    Setup,
] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64
    using Random: seed!
    seed!(1)

    unary = (
        +,
        -,
        abs,
        abs2,
        sign,
        inv,
        sqrt,
        cbrt,
        exp,
        exp2,
        exp10,
        expm1,
        log,
        log2,
        log10,
        log1p,
        sin,
        cos,
        tan,
        sec,
        csc,
        cot,
        asin,
        acos,
        atan,
        sinh,
        cosh,
        tanh,
        asinh,
        sech,
        csch,
        coth,
        acsch,
        asech,
        sinpi,
        cospi,
        sind,
        cosd,
        tand,
        asind,
        acosd,
        atand,
        deg2rad,
        rad2deg,
        mod2pi,
        significand,
        nextfloat,
        prevfloat,
        eps,
        floor,
        ceil,
        trunc,
        round,
        float,
    )
    for T in FloatTypes, f in unary
        # (DoubleFloats' `cbrt(::Double64)` returns a tuple, so it cannot be wrapped.)
        T === Double64 && f === cbrt && continue
        for _ = 1:5
            x = T(rand()) * T(0.9) + T(0.05)   # in (0, 1) so every domain is valid
            r = f(x)
            cr = f(loose(x))
            @test cr isa Checked{T}
            @test isequal(unchecked(cr), r)
        end
    end

    # Domain-restricted or type-restricted functions
    for T in FloatTypes
        x = T(1.5)
        @test unchecked(acosh(loose(x))) == acosh(x)
        @test unchecked(acoth(loose(x))) == acoth(x)
        @test unchecked(asec(loose(x))) == asec(x)
        @test unchecked(acsc(loose(x))) == acsc(x)
        @test unchecked(acot(loose(x))) == acot(x)
        @test unchecked(atanh(loose(T(0.5)))) == atanh(T(0.5))
        @test exponent(loose(x)) === exponent(x)
        @test unchecked(frexp(loose(x))[1]) == frexp(x)[1]
        @test frexp(loose(x))[2] == frexp(x)[2]
        @test unchecked(ldexp(loose(x), 3)) == ldexp(x, 3)
        @test unchecked(nextfloat(loose(x), 7)) == nextfloat(x, 7)
        @test unchecked(prevfloat(loose(x), 7)) == prevfloat(x, 7)
        @test unchecked.(sincos(loose(x))) == sincos(x)
        @test unchecked.(sincospi(loose(x))) == sincospi(x)
        @test unchecked.(sincosd(loose(x))) == sincosd(x)
        @test unchecked.(modf(loose(x))) == modf(x)
        @test unchecked.(minmax(loose(x), loose(T(2)))) == minmax(x, T(2))
        T <: Base.IEEEFloat && @test bitstring(loose(x)) == bitstring(x)
    end
    if isdefined(Base, :tanpi)
        @test unchecked(tanpi(loose(0.3))) == tanpi(0.3)
    end
end

@testitem "binary functions match the wrapped type" tags=[:unit, :validation, :fast] setup=[
    Setup,
] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64
    using Random: seed!
    seed!(2)

    binary = (
        +,
        -,
        *,
        /,
        ^,
        atan,
        hypot,
        log,
        mod,
        rem,
        copysign,
        flipsign,
        min,
        max,
        fld,
        cld,
        div,
    )
    for T in FloatTypes, f in binary
        for _ = 1:5
            x = T(rand()) * 3 + T(0.5)
            y = T(rand()) * 3 + T(0.5)
            r = f(x, y)
            # Checked op Checked
            cr = f(loose(x), loose(y))
            @test cr isa Checked{T}
            @test isequal(unchecked(cr), r)
            # Checked op T and T op Checked (through promotion)
            @test isequal(unchecked(f(loose(x), y)), r)
            @test isequal(unchecked(f(x, loose(y))), r)
        end
        # With integers and rationals (through promotion).  (Base's mixed-type `hypot` uses a
        # different algorithm from the same-type one, so compare against the promoted call.)
        x = T(2.5)
        ref(x, v) = f === hypot ? f(promote(x, v)...) : f(x, v)
        @test isequal(unchecked(f(loose(x), 2)), ref(x, 2))
        @test isequal(unchecked(f(3, loose(x))), ref(3, x))
        @test isequal(unchecked(f(loose(x), 1 // 4)), ref(x, 1 // 4))
    end

    for T in FloatTypes
        x, y, z = T(1.5), T(-2.25), T(0.75)
        @test unchecked(fma(loose(x), loose(y), loose(z))) == fma(x, y, z)
        @test unchecked(muladd(loose(x), loose(y), loose(z))) == muladd(x, y, z)
        @test unchecked(muladd(loose(x), y, z)) == muladd(x, y, z)
        @test unchecked(divrem(loose(x), loose(z))[1]) == divrem(x, z)[1]
        @test unchecked(divrem(loose(x), loose(z))[2]) == divrem(x, z)[2]
        @test unchecked(fldmod(loose(x), loose(z))[2]) == fldmod(x, z)[2]
        @test unchecked(rem2pi(loose(T(7)), RoundNearest)) == rem2pi(T(7), RoundNearest)
        # (DoubleFloats' `rem(::Double64, ::Double64, ::RoundingMode)` overflows the stack.)
        for r in (RoundNearest, RoundToZero, RoundUp, RoundDown, RoundFromZero)
            T === Double64 && continue
            @test unchecked(rem(loose(x), loose(z), r)) == rem(x, z, r)
            @test unchecked(div(loose(x), loose(z), r)) == div(x, z, r)
        end
        @test unchecked(loose(x)^3) == x^3
        @test unchecked(loose(x)^-2) == x^-2
        @test unchecked(loose(x)^0) == one(T)
        @test unchecked(loose(x)^2) == x^2                     # literal_pow
        @test unchecked(loose(x)^-1) == x^-1                   # literal_pow special case
        @test unchecked(2^loose(x)) == 2^x
        @test unchecked(loose(x)^T(0.5)) == x^T(0.5)
        @test unchecked(loose(x) % z) == x % z
        @test unchecked(clamp(loose(x), z, T(1))) == clamp(x, z, T(1))
        @test unchecked(clamp(loose(x), 0, 1)) == clamp(x, 0, 1)
        @test unchecked(evalpoly(loose(x), (1, 2, 3))) == evalpoly(x, (1, 2, 3))
        @test unchecked(loose(x) * true) == x && unchecked(loose(x) * false) == zero(T)
        @test unchecked(loose(x) * π) == x * π
        @test unchecked(π * loose(x)) == π * x
        @test unchecked(loose(x) + ℯ) == x + ℯ
    end
end

@testitem "comparisons, hashing, and predicates" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64

    for T in FloatTypes
        a, b = loose(T(1)), loose(T(2))
        @test a < b && a <= b && b > a && b >= a && a != b && a == a
        @test a < 2 && 1 < b && a <= 1 && a >= 1 && a == 1 && a == T(1)
        @test isless(a, b) && !isless(b, a)
        @test cmp(a, b) == -1 && cmp(b, a) == 1 && cmp(a, a) == 0
        @test isequal(a, T(1)) && isequal(a, a) && !isequal(a, b)
        @test hash(a) == hash(T(1))                      # consistent with the wrapped value
        T === Double64 || @test hash(a) == hash(1)       # (DoubleFloats' hash is not)
        @test length(unique([a, loose(T(1)), b])) == 2
        @test sort([b, a]) == [a, b]
        @test minimum([b, a]) == a && maximum([a, b]) == b
        @test extrema([b, a]) == (a, b)
        @test loose(T(0)) == loose(-T(0))                # not `===` on the bits
        @test isequal(loose(T(NaN)), loose(T(NaN)))      # total order
        @test (loose(T(NaN)) == loose(T(NaN))) == (T(NaN) == T(NaN))   # whatever T does
        @test isless(loose(T(1)), loose(T(NaN))) == isless(T(1), T(NaN))
        @test a ≈ 1 && a ≈ T(1) && 1 ≈ a && a ≈ a && isapprox(a, b; atol = 2)
        @test !(a ≈ b)
        @test [a, b] ≈ [1, 2]
        @test Base.rtoldefault(typeof(a)) == Base.rtoldefault(T)

        x = loose(T(2.5))
        @test !isnan(x) &&
              !isinf(x) &&
              isfinite(x) &&
              !iszero(x) &&
              !isone(x) &&
              !signbit(x)
        @test !isinteger(x) &&
              isinteger(a) &&
              !issubnormal(x) &&
              isodd(a) &&
              iseven(b) &&
              isreal(x)
        @test iszero(zero(x)) && isone(one(x)) && signbit(-x)
        @test isnan(loose(T(NaN))) && isinf(loose(T(Inf))) && !isfinite(loose(T(-Inf)))
    end
    @test issubnormal(loose(1e-310)) && issubnormal(loose(1.0f-40))
end

@testitem "conversions and type properties" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64

    for T in FloatTypes
        X = typeof(loose(T(1)))
        x = X(T(2.5))
        @test Float64(x) === 2.5
        @test Float32(x) === 2.5f0
        @test Float16(x) === Float16(2.5)
        @test BigFloat(x) == 2.5
        @test Int(X(T(2))) === 2 && Int8(X(T(2))) === Int8(2)
        @test BigInt(X(T(2))) == 2
        @test Bool(X(T(1))) === true && Bool(X(T(0))) === false
        @test_throws InexactError Bool(x)
        @test Double64(x) == 2.5
        @test float(x) === x && AbstractFloat(x) === x && float(X) === X
        @test Complex(x) isa Complex{X}
        @test convert(X, x) === x
        @test convert(AbstractFloat, x) === x
        @test convert(Float64, x) === 2.5           # X has no precision check
        @test big(x) isa Checked{BigFloat} && flags(big(x)) == flags(x)
        @test widen(X) === Checked{widen(T),flags(X)...}
        if T !== Double64   # (DoubleFloats truncates `Int(2.5)` and lacks UInt/unsafe_trunc/decompose)
            @test UInt(X(T(2))) === UInt(2)
            @test_throws InexactError Int(x)
            @test unsafe_trunc(Int, x) === 2
            @test Base.decompose(x) == Base.decompose(T(2.5))
            @test Rational(x) == 5 // 2 && Rational{Int32}(x) == 5 // 2
        end

        # round/floor/ceil/trunc, with and without target types and digits
        y = X(T(2.567))
        for r in (
            RoundNearest,
            RoundToZero,
            RoundUp,
            RoundDown,
            RoundFromZero,
            RoundNearestTiesAway,
            RoundNearestTiesUp,
        )
            @test unchecked(round(y, r)) == round(T(2.567), r)
        end
        @test unchecked(round(y; digits = 1)) == round(T(2.567); digits = 1)
        @test unchecked(round(y; sigdigits = 2)) == round(T(2.567); sigdigits = 2)
        @test unchecked(round(y, RoundUp; digits = 1)) ==
              round(T(2.567), RoundUp; digits = 1)
        @test unchecked(floor(y; digits = 1)) == floor(T(2.567); digits = 1)
        @test round(Int, y) === 3 &&
              floor(Int, y) === 2 &&
              ceil(Int, y) === 3 &&
              trunc(Int, y) === 2
        @test round(Int, y, RoundDown) === 2
        # (DoubleFloats lacks `trunc(::Type{Int8}, ::Double64)` on Julia 1.10.)
        T === Double64 || @test round(Int8, y) === round(Int8, T(2.567))
        if T <: Base.IEEEFloat   # (Base has no `round(Bool, ::BigFloat)`)
            @test round(Bool, X(T(0.6))) === true && trunc(Bool, X(T(0.6))) === false
            @test floor(Bool, X(T(0.6))) === false && ceil(Bool, X(T(0.6))) === true
        end
        @test round(Int, X(T(2.5))) === round(Int, T(2.5))
        T === BigFloat || @test round(Int, X(T(2.5)), RoundNearestTiesAway) ===
              round(Int, T(2.5), RoundNearestTiesAway)

        # Type-level properties equal those of T, wrapped
        for f in (zero, one, typemin, typemax, floatmin, floatmax, maxintfloat, eps)
            v = f(X)
            @test v isa X
            @test isequal(unchecked(v), f(T))
        end
        @test precision(X) == precision(T)
        @test precision(x) == precision(T(2.5))
        @test oneunit(X) == 1 && oneunit(x) == 1
    end
    @test Base.uinttype(typeof(loose(1.0))) === UInt64
    @test Base.exponent_bits(typeof(loose(1.0))) === 11
    @test Base.significand_bits(typeof(loose(1.0f0))) === 23
end

@testitem "arrays, LinearAlgebra, Random, Printf, Complex" tags=[:integration, :fast] setup=[
    Setup,
] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64
    using LinearAlgebra: norm, dot, det, tr, lu
    using Random: seed!, randn, randexp
    using Printf: @sprintf
    seed!(3)

    for T in FloatTypes
        X = typeof(loose(T(1)))
        A = randn(T, 4, 4)
        v = randn(T, 4)
        cA, cv = loose(A), loose(v)
        @test cA isa Matrix{X}
        @test unchecked(cA * cv) ≈ A * v
        @test unchecked(cA * cA) ≈ A * A
        @test unchecked(cA') == A'
        @test unchecked(sum(cA)) ≈ sum(A)
        @test unchecked(prod(cv)) ≈ prod(v)
        @test unchecked(norm(cv)) ≈ norm(v)
        @test unchecked(dot(cv, cv)) ≈ dot(v, v)
        @test unchecked(det(cA)) ≈ det(A)
        @test unchecked(tr(cA)) ≈ tr(A)
        @test unchecked(cA \ cv) ≈ A \ v
        @test unchecked(lu(cA).U) ≈ lu(A).U
        @test unchecked(cv .+ 1) == v .+ 1
        @test unchecked(cv .* cv) == v .* v
        @test unchecked(sqrt.(abs.(cv))) == sqrt.(abs.(v))
        @test unchecked(cumsum(cv)) == cumsum(v)
        @test unchecked(zeros(X, 2)) == zeros(T, 2)
        @test unchecked(ones(X, 2)) == ones(T, 2)
        @test unchecked(fill(X(2), 2)) == fill(T(2), 2)
        @test eltype(similar(cv)) === X
        @test unchecked(X[1, 2, 3]) == T[1, 2, 3]
        @test unchecked(range(X(0), X(1); length = 3)) == range(T(0), T(1); length = 3)

        # Random: values are drawn from the underlying type
        @test rand(X) isa X
        @test randn(X) isa X
        @test randexp(X) isa X
        @test rand(X, 3) isa Vector{X}
        @test randn(X, 2, 2) isa Matrix{X}
        @test all(0 .<= rand(X, 100) .< 1)
        @test rand(Complex{X}) isa Complex{X}

        # Complex
        # Complex: identical to the wrapped type unless that type specializes the complex
        # functions itself (DoubleFloats does), in which case only approximately.
        z = Complex(loose(T(1)), loose(T(2)))
        w = Complex(T(1), T(2))
        cmp = T === Double64 ? ((a, b) -> isapprox(a, b; rtol = 8eps(T))) : (==)
        @test cmp(unchecked(abs(z)), abs(w))
        @test cmp(unchecked(z * z), w * w)
        @test cmp(unchecked(exp(z)), exp(w))
        @test cmp(unchecked(sqrt(z)), sqrt(w))
        @test cmp(unchecked(z / z), w / w)
        @test cmp(unchecked(angle(z)), angle(w))
    end

    x = loose(1.5)
    @test @sprintf("%.3f", x) == "1.500"
    @test @sprintf("%e", x) == "1.500000e+00"
    @test @sprintf("%g %s", x, x) == "1.5 1.5"
end
