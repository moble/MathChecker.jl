# Shared test infrastructure.  (Test items themselves live in the other test-*.jl files.)

@testmodule Setup begin
    using DoubleFloats: Double64
    using MathChecker: Checked, checked, unchecked, flags, CheckError

    # The float types that every numerical test should sweep over.
    const FloatTypes = (Float32, Float64, Double64, BigFloat)

    # Every flag on / off.
    const ALL_ON = (
        precision = true,
        nan = true,
        inf = true,
        cancellation = true,
        absorption = true,
        subnormal = true,
        rounding = true,
    )
    const ALL_OFF = (
        precision = false,
        nan = false,
        inf = false,
        cancellation = false,
        absorption = false,
        subnormal = false,
        rounding = false,
    )

    # A Checked with only the runtime-unambiguous checks (NaN and Inf), no precision check,
    # so that mixed-type arithmetic in tests is allowed.
    loose(x) = checked(x; precision = false)

    # Evaluate `f` and return the CheckError it signals, or `nothing` if none.
    function signalled(f)
        try
            f()
            return nothing
        catch e
            e isa CheckError && return e
            rethrow()
        end
    end

    # Does `f()` throw a MethodError that comes from MathChecker's Precision machinery?
    function precision_error(f)
        try
            f()
            return false
        catch e
            e isa MethodError || rethrow()
            return e.f === MathChecker.mixed_precision
        end
    end
    using MathChecker

    # Render an exception with its error hints, as the REPL would.
    hinted(e) = sprint(showerror, e)
end
