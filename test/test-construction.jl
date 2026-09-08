@testitem "constructors and flags" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, ALL_ON, ALL_OFF

    for T in FloatTypes
        x = Checked{T}(1)
        @test x isa Checked{T}
        @test valuetype(x) === T
        @test valuetype(typeof(x)) === T
        @test flags(x) === DEFAULT_FLAGS
        @test flags(typeof(x)) === DEFAULT_FLAGS
        @test unchecked(x) == 1
        @test typeof(unchecked(x)) === T

        # Full positional form
        y = Checked{T,false,true,false,1e-3,true,false,true}(T(2))
        @test flags(y) == (
            precision = false,
            nan = true,
            inf = false,
            cancellation = 1e-3,
            absorption = true,
            subnormal = false,
            rounding = true,
        )
        @test unchecked(y) == 2

        # Keyword forms change only the flags named
        z = Checked{T}(3; cancellation = true, precision = false)
        @test flags(z) == merge(DEFAULT_FLAGS, (cancellation = true, precision = false))
        @test flags(Checked(T(3); rounding = true)) ==
              merge(DEFAULT_FLAGS, (rounding = true,))
        @test flags(checked(T(3); absorption = 1e-8)) ==
              merge(DEFAULT_FLAGS, (absorption = 1e-8,))
        @test flags(checked(T(3); ALL_ON...)) == ALL_ON
        @test flags(checked(T(3); ALL_OFF...)) == ALL_OFF

        # Re-wrapping a Checked keeps its flags unless told otherwise
        w = checked(z; nan = false)
        @test flags(w) == merge(flags(z), (nan = false,))
        @test unchecked(w) == 3
        @test Checked(z) === z
        @test Checked{T}(z) === z
        @test typeof(z)(z) === z

        # Type-level constructor
        X = checked(T; nan = true, inf = false)
        @test X <: Checked{T}
        @test flags(X) == merge(DEFAULT_FLAGS, (inf = false,))
        @test flags(checked(X; inf = true)) == DEFAULT_FLAGS
        @test eltype(zeros(X, 2)) === X
        @test all(iszero, zeros(X, 2))
    end

    # Non-float reals become Float64
    @test Checked(1) isa Checked{Float64}
    @test Checked(1 // 3) isa Checked{Float64}
    @test checked(1) isa Checked{Float64}
    @test checked(1 // 3) isa Checked{Float64}
    @test unchecked(checked(1 // 3)) == 1 / 3
    @test unchecked(Checked{Float32}(1 // 3)) === Float32(1 // 3)
    @test unchecked(Checked{Float32}(π)) === Float32(π)
    @test unchecked(Checked{Float64}(true)) === 1.0

    # Constructors never signal, so sentinels can be built
    @test isnan(Checked{Float64}(NaN))
    @test isinf(Checked{Float64}(Inf))
    @test isnan(Checked{Float64}(NaN; nan = true))
    @test issubnormal(checked(1e-310; subnormal = true))
    A = fill(Checked{Float64}(NaN), 3)
    @test all(isnan, A)
    @test_throws NaNError A[1] + 1

    # Explicit constructors are exempt from the Precision check
    @test Checked{Float32}(1.0) isa Checked{Float32}
    @test Checked{Float64}(Checked{Float32}(1)) isa Checked{Float64}
    @test Float64(Checked{Float32}(1)) === 1.0
end

@testitem "invalid construction" tags=[:unit, :fast] begin
    x = Checked{Float64}(1.0)
    @test_throws ArgumentError Checked{typeof(x)}(1.0)               # no nesting
    @test_throws Exception Checked{typeof(x)}(x)
    @test_throws ArgumentError Checked{Float64,1,true,true,false,false,false,false}(1.0)
    @test_throws ArgumentError Checked{Float64,true,1,true,false,false,false,false}(1.0)
    @test_throws ArgumentError Checked{Float64,true,true,true,-1.0,false,false,false}(1.0)
    @test_throws ArgumentError Checked{Float64,true,true,true,false,1.0f0,false,false}(1.0)
    @test_throws ArgumentError Checked{Float64,true,true,true,false,false,false,nothing}(
        1.0,
    )
    @test_throws ArgumentError checked(1.0; bogus = true)
    @test_throws ArgumentError Checked{Float64}(1.0; nans = true)
end

@testitem "checked / unchecked on containers" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes

    for T in FloatTypes
        v = T[1, 2, 3]
        cv = checked(v; cancellation = true)
        @test cv isa Vector{<:Checked{T}}
        @test flags(eltype(cv)).cancellation === true
        @test unchecked(cv) == v
        @test typeof(unchecked(cv)) === Vector{T}

        M = reshape(v, 3, 1)
        @test unchecked(checked(M)) == M

        z = Complex(T(1), T(2))
        cz = checked(z)
        @test cz isa Complex{<:Checked{T}}
        @test unchecked(cz) === z
        @test unchecked(checked([z, z])) == [z, z]

        t = (T(1), 2, T(3))
        ct = checked(t)
        @test ct[1] isa Checked{T}
        @test ct[2] isa Checked{Float64}
        @test unchecked(ct) == (T(1), 2.0, T(3))
    end

    # unchecked is the identity on things that are not Checked
    @test unchecked(1) === 1
    @test unchecked("s") === "s"
    @test unchecked([1, 2]) == [1, 2]
    @test unchecked(nothing) === nothing
end

@testitem "show and print" tags=[:unit, :fast] begin
    x = Checked{Float64}(1.5)
    C = repr(Checked)   # "Checked" or "MathChecker.Checked", depending on what is in scope
    @test repr(x) == "$C{Float64}(1.5)"
    @test string(x) == "1.5"
    @test "$x" == "1.5"
    @test sprint(print, x) == "1.5"
    @test eval(Meta.parse(repr(x))) === x            # show round-trips

    y = checked(1.5; cancellation = 1e-6)
    @test repr(y) == "$C{Float64, true, true, true, 1.0e-6, false, false, false}(1.5)"
    @test eval(Meta.parse(repr(y))) === y

    # Inside a typed container only the values are shown
    s = repr([x, x + 1])
    @test occursin("[1.5, 2.5]", s)
    @test !occursin("{Float64}(1.5)", s)
    s = sprint(show, MIME("text/plain"), [x, x + 1])
    @test occursin("1.5", s) && occursin("Checked{Float64", s)

    z = Checked{Float32}(1)
    @test repr(z) == "$C{Float32}(1.0f0)"
    @test repr(Checked{BigFloat}(1)) == "$C{BigFloat}(1.0)"
end
