@testitem "promotion unions flags" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, ALL_ON, ALL_OFF

    for T in FloatTypes
        a = checked(T(1); ALL_OFF...)
        n = checked(T(1); ALL_OFF..., nan = true)
        i = checked(T(1); ALL_OFF..., inf = true)
        @test flags(n + i) == merge(ALL_OFF, (nan = true, inf = true))
        @test flags(i + n) == flags(n + i)
        @test flags(a + n) == flags(n)
        @test flags(a + a) == flags(a)
        @test flags(checked(T(1); ALL_ON...) + a) == ALL_ON
        @test promote_type(typeof(n), typeof(i)) === typeof(n + i)
        @test promote_type(typeof(i), typeof(n)) === typeof(n + i)
        # Union is applied by all binary operations and by array construction
        @test flags([n, i][1]) == flags(n + i)
        @test flags(max(n, i)) == flags(n + i)
        @test flags(hypot(n, i)) == flags(n + i)
        @test (n < i) === false

        # Configured flags: stricter wins, symmetrically
        c3 = checked(T(1); ALL_OFF..., cancellation = 1e-3)
        c6 = checked(T(1); ALL_OFF..., cancellation = 1e-6)
        ct = checked(T(1); ALL_OFF..., cancellation = true)
        @test flags(c3 + c6).cancellation == 1e-3
        @test flags(c6 + c3).cancellation == 1e-3
        @test flags(c3 + ct).cancellation === true
        @test flags(ct + c3).cancellation === true
        @test flags(c3 + a).cancellation == 1e-3
        s1 = checked(T(1); ALL_OFF..., absorption = 1e-2)
        s2 = checked(T(1); ALL_OFF..., absorption = 1e-4)
        @test flags(s1 + s2).absorption == 1e-2 == flags(s2 + s1).absorption
        p64 = checked(T(1); ALL_OFF..., precision = Float64)
        p32 = checked(T(1); ALL_OFF..., precision = Float32)
        pt = checked(T(1); ALL_OFF..., precision = true)
        @test flags(p64 + p32).precision === Union{Float32,Float64}
        @test flags(p32 + p64).precision === Union{Float32,Float64}
        @test flags(p64 + pt).precision === true
        @test flags(pt + p64).precision === true
    end
end

@testitem "promotion with other number types" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, loose
    using DoubleFloats: Double64

    for T in FloatTypes
        X = typeof(loose(T(1)))
        F = flags(X)
        @test promote_type(X, T) === X
        @test promote_type(T, X) === X
        @test promote_type(X, Int) === X
        @test promote_type(X, Bool) === X
        @test promote_type(X, Rational{Int}) === X
        @test promote_type(X, typeof(π)) === X
        @test promote_type(typeof(π), X) === X
        @test promote_type(X, BigFloat) === Checked{BigFloat,F...}
        @test promote_type(BigFloat, X) === Checked{BigFloat,F...}
        @test promote_type(X, Float64) === Checked{promote_type(T, Float64),F...}
        @test promote_type(Float32, X) === Checked{promote_type(T, Float32),F...}
        @test promote_type(X, Double64) === Checked{promote_type(T, Double64),F...}
        @test promote_type(X, Complex{Int}) === Complex{X}
        @test promote_type(Complex{Float64}, X) ===
              Complex{Checked{promote_type(T, Float64),F...}}
        @test promote_type(X, Checked{Float64,F...}) ===
              Checked{promote_type(T, Float64),F...}
        # Actual values
        @test loose(T(1)) + 1 // 2 isa X
        @test loose(T(1)) + π isa X
        @test loose(T(1)) + im isa Complex{X}
        @test loose(T(1)) + BigInt(1) isa Checked{promote_type(T, BigInt)}
        @test promote_type(X, BigInt) ===
              promote_type(BigInt, X) ===
              Checked{promote_type(T, BigInt),F...}
    end
end
