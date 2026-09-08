@testitem "inference and allocations" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: FloatTypes, ALL_ON, ALL_OFF

    f(a, b) = sqrt(a * a + b * b) / (a - b) + fma(a, b, a) - hypot(a, b) * 2 + a^2 - b^-1
    g(a, b) = (a < b) ? round(a + b; digits = 1) : mod(a, b) + min(a, b)

    # (Rounding is left off: these inputs round, and a firing check is not the fast path.)
    for T in (Float32, Float64),
        fl in (
            DEFAULT_FLAGS,
            ALL_OFF,
            merge(ALL_ON, (rounding = false,)),
            merge(ALL_OFF, (cancellation = 1e-3, swamping = true)),
        )

        a, b = checked(T(3); fl...), checked(T(1.5); fl...)
        @test @inferred(f(a, b)) isa typeof(a)
        @test @inferred(g(a, b)) isa typeof(a)
        f(a, b)
        g(a, b)
        @test @allocated(f(a, b)) == 0
        @test @allocated(g(a, b)) == 0
        @test @inferred(a + 1) isa typeof(a)
        @test @inferred(a * 2) isa typeof(a)
        @test @inferred(a + b) isa typeof(a)
        @test @inferred(a < b) isa Bool
        @test @inferred(promote(a, 1)) isa Tuple{typeof(a),typeof(a)}
    end
    # Mixed flags promote inferrably
    a = checked(1.0; nan = true, inf = false)
    b = checked(1.0; nan = false, inf = true)
    @test @inferred(a + b) isa Checked{Float64}
    @test @allocated(a + b) == 0
    # (The keyword constructors depend on constant propagation of the flag *values*, which
    # `@inferred` cannot see; the positional form is always inferrable.)
    @test @inferred(Checked{Float64,true,true,true,1e-3,false,false,false}(1)) isa
          Checked{Float64}
    @test @inferred(flags(a)) isa NamedTuple
    @test @inferred(unchecked(a)) === 1.0
    @test @inferred(unchecked([a, a])) isa Vector{Float64}
end

@testitem "disabled checks compile away" tags=[:unit, :validation, :fast] setup=[Setup] begin
    using .Setup: ALL_OFF
    using InteractiveUtils: code_llvm

    X = checked(Float64; ALL_OFF...)
    h(a, b) = (a + b) * (a - b) / sqrt(a * b)
    # With every flag off, the generated code is the same handful of float instructions as
    # for a plain Float64 (including Base's own domain check in `sqrt`), and nothing else.
    llvm = sprint(code_llvm, h, (X, X))
    plain = sprint(code_llvm, h, (Float64, Float64))
    for instr in ("fadd", "fsub", "fmul", "fdiv", "call", "br ", "fcmp")
        @test count(instr, llvm) == count(instr, plain)
    end
    @test !occursin("fail", llvm)
    # With the NaN and Inf checks on, the failure path is present but out of line.
    Y = checked(Float64; precision = false)
    llvm = sprint(code_llvm, h, (Y, Y))
    @test occursin("fail", llvm)
    @test count("fadd", llvm) == count("fadd", plain)
end

@testitem "Aqua" tags=[:unit, :slow] begin
    using Aqua
    Aqua.test_all(MathChecker; ambiguities = false, persistent_tasks = false)
    # Ambiguities: only those involving this package's own methods.
    Aqua.test_ambiguities(MathChecker; recursive = true)
end

@testitem "ExplicitImports" tags=[:unit, :slow] begin
    using ExplicitImports
    @test check_no_implicit_imports(MathChecker) === nothing
    @test check_no_stale_explicit_imports(MathChecker) === nothing
    @test check_all_explicit_imports_via_owners(MathChecker) === nothing
    @test check_all_qualified_accesses_via_owners(MathChecker) === nothing
    @test check_no_self_qualified_accesses(MathChecker) === nothing
end
