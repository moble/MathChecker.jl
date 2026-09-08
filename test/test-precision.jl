# The Precision check: a dispatch-time (MethodError) failure on implicit mixing of float
# types, with an explanatory hint.

@testitem "Precision check forbids implicit mixing" tags=[:unit, :validation, :fast] setup=[
    Setup,
] begin
    using .Setup: precision_error, hinted
    using DoubleFloats: Double64

    pairs = (
        (Float32, Float64),
        (Float64, Float32),
        (Float64, Double64),
        (Double64, Float64),
        (Float32, BigFloat),
        (BigFloat, Float64),
        (Double64, BigFloat),
        (Float16, Float32),
    )
    for (T, S) in pairs
        x = Checked{T}(1)
        s = S(0.5)
        fs = Any[
            ()->x+s,
            ()->s+x,
            ()->x*s,
            ()->s/x,
            ()->x^s,
            ()->hypot(x, s),
            ()->atan(s, x),
            ()->fma(x, x, s),
            ()->muladd(x, s, x),
            ()->min(x, s),
            ()->[x, s],
            ()->promote(x, s),
            ()->convert(typeof(x), s),
        ]
        # Comparisons go through promotion too, unless the other type defines its own mixed
        # `(::Real, ::S)` comparison methods, as DoubleFloats does; those bypass the check.
        S === Double64 || append!(fs, Any[()->x<s, ()->x==s, ()->x≈s])
        for f in fs
            @test precision_error(f)
        end
        # (`copysign(x, s)` only reads the sign bit of `s` and never promotes.)
        @test copysign(x, -s) == -1
        # Mixing two Checked values of different value types, if either is strict
        y = Checked{S}(1)
        @test precision_error(() -> x + y)
        @test precision_error(() -> x + checked(S(1); precision = false))
        @test precision_error(() -> checked(T(1); precision = false) + y)
        # Storing into a plain array of another type (an implicit convert) — for Base's
        # float types; conversion to a third-party float goes through its own constructor.
        if S <: Union{Base.IEEEFloat,BigFloat}
            @test precision_error(() -> setindex!(S[0], x, 1))
            @test precision_error(() -> convert(S, x))
            @test precision_error(() -> S[x])
        else
            @test S[x] == [1]
        end

        # Explicit conversions are always allowed
        @test S(x) == 1
        @test Checked{S}(x) == 1
        @test unchecked(Checked{S}(s)) == S(0.5)
        @test Checked{S}(x) isa Checked{S}
        @test typeof(Checked{S}(x)) === typeof(Checked{S}(1))
        # A whitelist on one side does not override strictness on the other
        @test precision_error(() -> checked(S(1); precision = T) + x)
        @test checked(S(1); precision = T) + T(1) == 2
    end

    # The hint explains the problem
    x = Checked{Float32}(1)
    msg = try
        x + 1.0
        ""
    catch e
        hinted(e)
    end
    @test occursin("MathChecker:", msg)
    @test occursin("Checked{Float32, true, true, true, false, false, false, false}", msg)
    @test occursin("`Precision` check enabled", msg)
    @test occursin("mixing it with Float64", msg)
    @test occursin("`Float32` computation was contaminated by a `Float64`", msg)
    @test occursin("checked(x; precision=Float64)", msg)
    # ... in either order of the offending pair
    msg = try
        Float64[0.0][1] = x
        ""
    catch e
        hinted(e)
    end
    @test occursin("Checked{Float32, true, true, true, false, false, false, false}", msg)
    @test occursin("mixing it with Float64", msg)
    # ... and the stack trace points at the user's operation
    bt = try
        x + 1.0
    catch e
        stacktrace(catch_backtrace())
    end
    @test any(fr -> fr.func === :+, bt)
end

@testitem "Precision check permits exact types and whitelisted types" tags=[:unit, :fast] setup=[
    Setup,
] begin
    using .Setup: FloatTypes, precision_error
    using DoubleFloats: Double64

    for T in FloatTypes
        x = Checked{T}(2)
        X = typeof(x)
        # Exact types are always fine and produce the same T
        for v in (1, Int8(1), UInt(1), big(1), true, 1 // 3, big(1) // 3, π, ℯ)
            @test typeof(x + v) === X
            @test typeof(v * x) === X
            @test unchecked(x + v) == T(2) + T(v)
        end
        @test typeof(x^2) === X && typeof(x^-1) === X && typeof(2^x) === X
        @test typeof(x + x) === X
        @test typeof(x + T(1)) === X
        @test typeof(T(1) - x) === X
        @test unchecked(x * T(0.5)) == 1
        # Storing into an array of T is fine
        v = T[0]
        v[1] = x
        @test v[1] == 2
        @test convert(T, x) == 2 && convert(T, x) isa T
    end

    # A whitelist permits a specific foreign type, and the checked value absorbs it
    d = checked(Double64(1); precision = Float64)
    @test typeof(d * 0.5) === typeof(d)
    @test unchecked(d * 0.5) === Double64(0.5)
    @test precision_error(() -> d * 0.5f0)
    @test precision_error(() -> d * big(0.5))
    f = checked(1.0f0; precision = Union{Float64,Float16})
    @test typeof(f + 1.0) === typeof(f)
    @test typeof(f + Float16(1)) === typeof(f)
    @test unchecked(f + 1.0) === 2.0f0
    @test precision_error(() -> f + big(1.0))
    @test typeof(f + big(1)) === typeof(f)              # BigInt is exact, hence permitted
    # ... including in the other direction (storing into an array of the permitted type)
    v = Float64[0]
    v[1] = f
    @test v[1] === 1.0
    # A strict Checked still refuses a whitelisted-but-strict partner
    @test precision_error(() -> f + Checked{Float64}(1))
    @test typeof(f + checked(1.0; precision = false)) === typeof(f)

    # Turning the check off restores Julia's promotion
    g = checked(1.0f0; precision = false)
    @test typeof(g + 1.0) === typeof(checked(1.0; precision = false))
    @test typeof(g + big(1.0)) === typeof(checked(big(1.0); precision = false))
    @test typeof(g + Double64(1)) === typeof(checked(Double64(1); precision = false))
    @test typeof(g + 1) === typeof(g)
    @test typeof(g * π) === typeof(g)
    @test convert(Float64, g) === 1.0
end

@testitem "Precision check catches the motivating Double64 case" tags=[:validation, :fast] setup=[
    Setup,
] begin
    using .Setup: precision_error
    using DoubleFloats: Double64

    # A generic function with a hidden Float64 literal
    bad(x) = 0.5 * x + x^2
    good(x) = x / 2 + x^2
    d = Checked{Double64}(1)
    @test precision_error(() -> bad(d))
    @test unchecked(good(d)) === Double64(1.5)
    @test typeof(good(d)) === typeof(d)
    # The plain type would have silently done the wrong thing
    @test bad(Double64(1)) == 1.5
    # And the fix is easy to test for
    @test !precision_error(() -> bad(checked(Double64(1); precision = Float64)))
end
