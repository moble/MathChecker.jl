# Each runtime check: fires when it should, stays silent when it should, and reports
# useful information.

@testitem "NaN check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, signalled
    using DoubleFloats: Double64

    for T in FloatTypes
        z = checked(T(0); precision = false)
        inf = checked(T(Inf); precision = false, inf = false)
        nan = checked(T(NaN); precision = false)

        for f in (
            () -> z / z,
            () -> inf - inf,
            () -> inf * z,
            () -> nan + 1,
            () -> -nan,
            () -> sqrt(nan),
            () -> nan^2,
            () -> min(nan, z),
            () -> max(z, nan),
            () -> fma(nan, z, z),
            () -> rem(inf, T(2)),
            () -> round(nan),
            () -> abs(nan),
            () -> nan < 1,
            () -> 1 < nan,
            () -> nan <= nan,
            () -> z > nan,
            () -> nan >= z,
            () -> cmp(nan, z),
            () -> sincos(nan),
            () -> hypot(nan, z),
        )
            e = signalled(f)
            @test e isa NaNError
        end

        # The error carries the operation, operands, and result
        e = signalled(() -> z / z)
        @test e.op === (/)
        @test e.args == (T(0), T(0))
        @test isnan(e.result)
        @test sprint(showerror, e) ==
              "NaNError: $(repr(T(0))) / $(repr(T(0))) produced NaN (no operand was NaN)."
        e = signalled(() -> nan + 1)
        @test endswith(sprint(showerror, e), "produced NaN, propagating the NaN operand.")
        e = signalled(() -> nan < 1)
        @test e.op === (<) && e.result === false
        @test occursin(
            "produced false, consuming the NaN operand:\n       the NaN is silently lost here.",
            sprint(showerror, e),
        )

        # "Kills": a NaN operand consumed into an ordinary result signals too, including
        # through Base's non-promoting mixed-type methods
        one_ = checked(T(1); precision = false)
        for f in (
            () -> nan^0,
            () -> one_^nan,
            () -> copysign(one_, nan),
            () -> copysign(T(1), nan),
            () -> copysign(1, nan),
            () -> flipsign(nan, one_),
            () -> flipsign(T(1), nan),
            () -> hypot(nan, inf),
            () -> nan > 1,
            () -> 1 <= nan,
            () -> cmp(nan, nan),
            () -> cmp(nan, 1),
            () -> nan * 0,
            () -> min(nan, 1) + 0,
        )
            e = signalled(f)
            @test e isa NaNError
        end
        e = signalled(() -> nan^0)
        @test e.result == 1 && occursin("consuming the NaN operand", sprint(showerror, e))
        # (DoubleFloats' own `<(::Double64, ::Real)` bypasses promotion, hence the check.)
        T === Double64 || @test signalled(() -> T(1) < nan) isa NaNError

        # No false positives
        @test signalled(() -> z + 1) === nothing
        @test signalled(() -> inf + 1) === nothing          # Inf, not NaN (inf check is off)
        @test signalled(() -> isnan(nan)) === nothing
        @test signalled(() -> isequal(nan, nan)) === nothing
        @test signalled(() -> nan == nan) === nothing
        @test signalled(() -> isless(nan, z)) === nothing
        @test signalled(() -> isless(nan, T(0))) === nothing        # mixed isless, unchecked
        @test signalled(() -> isless(T(0), nan)) === nothing
        @test signalled(() -> isless(0, nan)) === nothing
        @test signalled(
            () -> isless(nan, checked(T(0); precision = false, inf = false)),
        ) === nothing
        @test signalled(() -> sort([nan, z, T(1)])) === nothing
        @test signalled(() -> sort([nan, z])) === nothing
        @test signalled(() -> hash(nan)) === nothing
        @test signalled(() -> string(nan)) === nothing

        # Off means off
        q = checked(T(0); precision = false, nan = false, inf = false)
        @test isnan(q / q)
        @test (q / q < 1) === false
    end
end

@testitem "Inf check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, signalled

    for T in FloatTypes
        one_ = checked(T(1); precision = false)
        z = checked(T(0); precision = false)
        big_ = checked(floatmax(T); precision = false)
        fs = Any[()->one_/z, ()->-one_/z, ()->log(z), ()->inv(z)]
        if T <: Base.IEEEFloat   # (the overflow behaviour of `floatmax` is type-specific)
            append!(
                fs,
                Any[
                    ()->big_*2,
                    ()->big_+big_,
                    ()->exp(big_),
                    ()->big_^2,
                    ()->ldexp(big_, 1),
                    ()->fma(big_, big_, z),
                    ()->nextfloat(big_),
                    ()->eps(checked(T(Inf); precision = false, inf = false)+0),
                ],
            )
        end
        for f in fs
            e = signalled(f)
            @test e isa Union{InfError,NaNError}
        end
        e = signalled(() -> one_ / z)
        @test e isa InfError
        @test e.result == T(Inf) && e.args == (T(1), T(0))
        @test sprint(showerror, e) ==
              "InfError: $(repr(T(1))) / $(repr(T(0))) produced $(repr(T(Inf))):\n       division by zero (the exact result is infinite)."
        @test occursin("division by zero", sprint(showerror, signalled(() -> log(z))))
        @test occursin("division by zero", sprint(showerror, signalled(() -> inv(z))))
        @test occursin(
            "an operand was already infinite",
            sprint(showerror, signalled(() -> checked(T(Inf); precision = false) + 1)),
        )
        e = signalled(() -> -one_ / z)
        @test e.result == -T(Inf)
        @test occursin("produced $(repr(-T(Inf))):", sprint(showerror, e))
        if T <: Base.IEEEFloat
            e = signalled(() -> big_ * 2)
            @test occursin(
                "overflow (the exact result is finite but exceeds floatmax($T)",
                sprint(showerror, e),
            )
        end

        # No false positives: constructing, comparing with, and inspecting Inf is fine
        inf = checked(T(Inf); precision = false)
        @test signalled(() -> one_ < inf) === nothing
        @test signalled(() -> typemax(typeof(one_))) === nothing
        @test signalled(() -> isinf(inf)) === nothing
        @test signalled(() -> big_ + 1) === nothing         # rounds back to floatmax
        @test signalled(() -> one_ / big_) === nothing
        @test (
            checked(T(1); precision = false, inf = false) /
            checked(T(0); precision = false, inf = false)
        ) == Inf
    end
end

@testitem "Subnormal check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: signalled
    using DoubleFloats: Double64

    for T in (Float32, Float64)
        tiny = checked(floatmin(T); precision = false, subnormal = true)
        e = signalled(() -> tiny / 2)
        @test e isa SubnormalError
        @test e.op === (/) && issubnormal(e.result)
        @test occursin("produced the subnormal number", sprint(showerror, e))
        @test occursin(
            "smaller than the smallest normal $T (floatmin = ",
            sprint(showerror, e),
        )
        @test signalled(() -> tiny * T(0.1)) isa SubnormalError
        @test signalled(() -> tiny - tiny * T(0.75)) isa SubnormalError
        @test signalled(() -> prevfloat(tiny)) isa SubnormalError
        @test signalled(() -> ldexp(tiny, -3)) isa SubnormalError
        # Underflow to zero counts too (IEEE UNDERFLOW), when the exact result is nonzero
        for f in (
            () -> tiny * tiny,
            () -> tiny / floatmax(T),
            () -> exp(checked(T(-1e6); precision = false, subnormal = true)),
            () -> ldexp(tiny, -2000),
            () -> tiny^3,
            () -> sinh(tiny / 8) * tiny,
        )
            e = signalled(f)
            @test e isa SubnormalError
        end
        e = signalled(() -> tiny * tiny)
        @test iszero(e.result)
        @test occursin("having underflowed:", sprint(showerror, e))
        @test occursin("smaller than the smallest positive $T (≈ ", sprint(showerror, e))
        # No false positives
        @test signalled(() -> tiny * 2) === nothing
        @test signalled(() -> tiny - tiny) === nothing          # zero is not subnormal
        @test signalled(() -> tiny * 0) === nothing             # exact zero
        @test signalled(() -> 0 / tiny) === nothing
        @test signalled(
            () -> tiny / checked(T(Inf); precision = false, subnormal = true, inf = false),
        ) === nothing
        @test signalled(() -> sin(checked(T(0); precision = false, subnormal = true))) ===
              nothing
        @test signalled(() -> checked(T(0); precision = false, subnormal = true)^2) ===
              nothing
        @test signalled(() -> tiny * 0) === nothing
        @test signalled(() -> sqrt(tiny)) === nothing
        # Off
        @test issubnormal(checked(floatmin(T); precision = false) / 2)
    end
    # Types without subnormals never report a subnormal, but they can still underflow to
    # zero: MPFR flushes anything below `floatmin(BigFloat)` to exactly 0.
    e = signalled(() -> checked(floatmin(BigFloat); subnormal = true) / 2)
    @test e isa SubnormalError && iszero(e.result)
    @test signalled(() -> checked(floatmin(BigFloat); subnormal = true) * 2) === nothing
    @test signalled(
        () -> checked(Double64(1e-300); precision = false, subnormal = true) / 1e10,
    ) === nothing
    @test MathChecker.issubnormal(1e-310) && !MathChecker.issubnormal(1.0)
    @test !MathChecker.issubnormal(big"1e-310") && !MathChecker.issubnormal(1 // 3)
end

@testitem "Rounding check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, signalled
    using DoubleFloats: Double64

    # Square the corrected result in high precision, to verify the reported residual.
    corrected_square(e) = setprecision(BigFloat, 1024) do
        (big(e.result) + big(e.residual))^2
    end

    for T in FloatTypes
        r(x) = checked(T(x); precision = false, rounding = true)
        # Exact operations do not signal
        for f in (
            () -> r(1) + r(2),
            () -> r(0.5) * r(0.25),
            () -> r(3) / r(4),
            () -> sqrt(r(16)),
            () -> r(1.5) - r(0.25),
            () -> r(1) + r(0),
            () -> r(0) * r(1e10),
            () -> sqrt(r(0)),
            () -> r(0.1) * 1,
            () -> r(0.1) / 1,
            () -> -r(0.1),
            () -> abs(r(-0.1)),
            () -> r(0.1) + 0,
        )
            @test signalled(f) === nothing
        end
        # Inexact operations do
        @test signalled(() -> r(1) / 3) isa RoundingError
        @test signalled(() -> sqrt(r(2))) isa RoundingError
        if T !== Double64   # (a double-double represents 1 + eps/4 exactly)
            @test signalled(() -> r(1) + eps(T) / 4) isa RoundingError
            @test signalled(() -> r(1) - eps(T) / 4) isa RoundingError
        end
        @test signalled(() -> r(1 + eps(T)) * r(1 + eps(T))) isa RoundingError

        e = signalled(() -> r(1) / 3)
        @test e.op === (/) && e.args == (T(1), T(3))
        @test abs(e.residual) < eps(T)
        @test occursin("which is inexact:\n       exact − computed ≈", sprint(showerror, e))
        @test occursin(r"\(\d.*ulps?\)", sprint(showerror, e))
        # The residual is the actual error of the rounded result
        @test setprecision(() -> 3 * (big(e.result) + big(e.residual)), BigFloat, 1024) ≈ 1 atol =
            eps(T)^2 * 10
        e = signalled(() -> sqrt(r(2)))
        @test corrected_square(e) ≈ 2 atol = eps(T)^2 * 100
    end
    # Non-finite results are left to the other checks
    @test signalled(
        () ->
            checked(floatmax(Float64); precision = false, inf = false, rounding = true) * 2,
    ) === nothing
end

@testitem "Cancellation check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, signalled

    for T in FloatTypes
        c(x; tol = true) = checked(T(x); precision = false, inf = false, cancellation = tol)
        δ = eps(T)^(3 // 4)            # much smaller than sqrt(eps): cancels >half the bits
        e = signalled(() -> c(1 + δ) - 1)
        @test e isa CancellationError
        @test e.op === (-) && e.args == (T(1 + δ), T(1))
        @test e.tolerance == sqrt(eps(T))
        @test bitslost(e) > precision(T) / 2
        @test bitslost(e) < precision(T)
        @test occursin(
            "significant bits: |result| / max(|a|, |b|) = ",
            sprint(showerror, e),
        )
        @test count('\n', sprint(showerror, e)) == 2
        @test occursin("is below the tolerance", sprint(showerror, e))
        @test e.ratio == abs(e.result) / T(1 + δ)
        @test signalled(() -> c(1 + δ) + (-1)) isa CancellationError
        @test signalled(() -> (-1) + c(1 + δ)) isa CancellationError
        @test signalled(() -> 1 - c(1 + δ)) isa CancellationError
        # Complete cancellation counts, and reports infinite bits lost
        e = signalled(() -> c(1) - 1)
        @test e isa CancellationError
        @test isinf(bitslost(e))
        @test occursin("cancelling all of", sprint(showerror, e))
        # fma / muladd: the additive step
        @test signalled(() -> fma(c(1), c(1 + δ), c(-1))) isa CancellationError
        @test signalled(() -> muladd(c(1), c(1 + δ), c(-1))) isa CancellationError

        # No false positives
        @test signalled(() -> c(1) + 1) === nothing
        @test signalled(() -> c(1) - 0.5) === nothing
        @test signalled(() -> c(1) - T(0.999)) === nothing     # loses ~10 bits, below default tolerance
        @test signalled(() -> c(0) + 0) === nothing            # both zero
        @test signalled(() -> c(0) - 0) === nothing
        @test signalled(() -> c(1) * 0) === nothing            # multiplication never cancels
        @test signalled(() -> c(1) / 3) === nothing
        @test signalled(() -> c(Inf) - 1) === nothing          # non-finite left to Inf check
        @test signalled(() -> c(1) ≈ c(1 + δ)) === nothing     # isapprox uses raw values
        @test signalled(() -> c(1) == c(1)) === nothing

        # Custom tolerance
        @test signalled(() -> c(1; tol = 1e-4) - T(0.999)) === nothing        # lost ~10 bits
        @test signalled(() -> c(1; tol = 1e-4) - T(0.99999)) isa CancellationError
        e = signalled(() -> c(1; tol = 1e-4) - T(0.99999))
        @test e.tolerance == T(1e-4)
        @test bitslost(e) ≈ log2(1 / 1e-5) atol = 0.2
        # Off
        @test signalled(() -> checked(T(1 + δ); precision = false) - 1) === nothing
    end
end

@testitem "Swamping check" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, signalled
    using DoubleFloats: Double64

    # A double-double can represent 1 + 5e-324 exactly, so it essentially never swamps;
    # the exact test is checked on the fixed-precision types only.
    for T in filter(!=(Double64), FloatTypes)
        s(x; tol = true) = checked(T(x); precision = false, inf = false, swamping = tol)
        tiny = eps(T) / 8
        e = signalled(() -> s(1) + tiny)
        @test e isa SwampingError
        @test e.op === (+) &&
              e.args == (T(1), T(tiny)) &&
              e.swamped == 2 &&
              e.tolerance === nothing
        @test occursin("was swamped:\n       |small| / |large| = ", sprint(showerror, e))
        @test occursin("made no difference to the result", sprint(showerror, e))
        @test e.ratio == T(tiny)
        e = signalled(() -> tiny + s(1))
        @test e isa SwampingError && e.swamped == 1
        e = signalled(() -> s(1) - tiny)
        @test e isa SwampingError && e.swamped == 2 && e.result == 1
        e = signalled(() -> tiny - s(1))
        @test e isa SwampingError && e.swamped == 1 && e.result == -1
        @test signalled(() -> fma(s(1), s(1), s(tiny))) isa SwampingError
        @test signalled(() -> muladd(s(tiny), s(1), s(1))) isa SwampingError
        @test signalled(() -> fma(s(1), s(tiny), s(1))).swamped == 1

        # No false positives
        @test signalled(() -> s(1) + 0) === nothing              # adding zero is not swamping
        @test signalled(() -> s(0) + 1) === nothing
        @test signalled(() -> s(1) + eps(T)) === nothing         # registers
        @test signalled(() -> s(1) + 1) === nothing
        @test signalled(() -> s(1) - 1) === nothing
        @test signalled(() -> s(1) * tiny) === nothing
        @test signalled(() -> s(Inf) + 1) === nothing            # non-finite left to Inf check
        @test signalled(() -> s(0) - 0) === nothing

        # Relative tolerance: partial swamping
        e = signalled(() -> s(1; tol = 1e-4) + T(1e-6))
        @test e isa SwampingError && e.swamped == 2 && e.tolerance == T(1e-4)
        @test occursin("is below the tolerance", sprint(showerror, e))
        @test e.ratio == T(1e-6)
        @test signalled(() -> s(1; tol = 1e-4) + T(1e-3)) === nothing
        @test signalled(() -> T(1e-6) - s(1; tol = 1e-4)).swamped == 1
        # Off
        @test signalled(() -> checked(T(1); precision = false) + tiny) === nothing
    end
    d(x) = checked(Double64(x); precision = false, swamping = true)
    @test signalled(() -> d(1) + 1e-300) === nothing         # representable, so not swamped
    @test signalled(() -> d(1) + 1e-30) === nothing
    @test signalled(
        () -> checked(Double64(1); precision = false, swamping = 1e-20) + 1e-30,
    ) isa SwampingError
end

@testitem "check ordering and combinations" tags=[:unit, :fast] setup=[Setup] begin
    using .Setup: ALL_ON, signalled

    # Non-finite results are reported by the NaN/Inf checks, not as cancellation/swamping
    x = checked(1.0; ALL_ON..., precision = false)
    @test signalled(() -> x / 0) isa InfError
    @test signalled(() -> x * 0 / 0) isa NaNError
    @test signalled(() -> (x * 0) / (x * 0)) isa NaNError
    # Cancellation is exact (Sterbenz), so the Rounding check stays quiet and the
    # Cancellation check reports it
    @test signalled(() -> x - 0.99999999999) isa CancellationError
    @test signalled(() -> x - 1) isa CancellationError
    # An inexact but well-conditioned subtraction is a rounding error only
    @test signalled(() -> x - 0.1) isa RoundingError
    # Everything else passes
    @test unchecked(x + 1) == 2
    @test unchecked(x * 4) == 4

    # Adding checks via re-wrapping
    y = checked(1.0)
    @test signalled(() -> y - 1) === nothing
    @test signalled(() -> checked(y; cancellation = true) - 1) isa CancellationError
end

@testitem "handlers" tags=[:unit, :fast] setup=[Setup] begin
    x = checked(1.0)
    @test MathChecker.handler[] === throw
    @test_throws InfError x / 0

    # collect_failures records everything and lets the computation finish
    result, failures = collect_failures() do
        (x / 0) * 0 + 1          # Inf, then NaN, then NaN again
    end
    @test isnan(result) && result isa typeof(x)
    @test length(failures) == 3
    @test failures[1] isa InfError && failures[2] isa NaNError && failures[3] isa NaNError
    @test failures[1].args == (1.0, 0.0)
    @test isequal(failures[3].args, (NaN, 1.0))
    result, failures = collect_failures(() -> x + 1)
    @test result == 2 && isempty(failures)

    # A custom handler
    seen = Ref(0)
    r = with_handler(() -> x / 0, e -> (seen[] += 1; nothing))
    @test r == Inf && seen[] == 1

    # warn_handler logs and continues
    r = @test_logs (:warn, r"InfError: 1.0 / 0.0 produced Inf:") with_handler(
        warn_handler,
    ) do
        x / 0
    end
    @test r == Inf

    # Handlers are dynamically scoped: nesting and restoring
    with_handler(e -> nothing) do
        @test x / 0 == Inf
        with_handler(throw) do
            @test_throws InfError x / 0
        end
        @test x / 0 == Inf
    end
    @test_throws InfError x / 0

    # ... and task-local
    t = Threads.@spawn with_handler(() -> (sleep(0.01); x / 0), e -> nothing)
    @test_throws InfError x / 0
    @test fetch(t) == Inf
end

@testitem "error display" tags=[:unit, :fast] begin
    using MathChecker: formatcall
    @test formatcall(+, (1.0, 2.0)) == "1.0 + 2.0"
    @test formatcall(-, (1.0,)) == "-(1.0)"
    @test formatcall(sqrt, (2.0,)) == "sqrt(2.0)"
    @test formatcall(fma, (1.0, 2.0, 3.0)) == "fma(1.0, 2.0, 3.0)"
    @test formatcall(round, (1.5, RoundNearest)) == "round(1.5, RoundNearest)"
    @test formatcall(<, (NaN, 1.0)) == "NaN < 1.0"
    @test formatcall(^, (2.0, 3)) == "2.0 ^ 3"
    @test formatcall(Base.literal_pow, (2.0, 3)) == "literal_pow(2.0, 3)"
    # Multi-line messages: continuation lines indented under the error name, one trailing period
    using MathChecker: message
    e = CancellationError(-, 1e-9, (1.000000001, 1.0), 1e-9, sqrt(eps()))
    lines = split(message(e), '\n')
    @test length(lines) == 3
    @test all(startswith(l, " "^7) for l in lines[2:end])
    @test endswith(lines[end], ".") && !endswith(lines[1], ".")
    @test sprint(showerror, e) == message(e)
    @test message(InfError(/, Inf, (1.0, 0.0))) ==
          "InfError: 1.0 / 0.0 produced Inf:\n       division by zero (the exact result is infinite)."
end
