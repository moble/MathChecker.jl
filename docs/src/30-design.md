```@meta
CurrentModule = MathChecker
```

# Design notes

## How a checked operation works

Every supported `Base` function has a method for `Checked` of the form

```julia
Base.sqrt(a::X) where {X<:Checked} = _wrap(X, sqrt, sqrt(a.val), a.val)
```

The operation is performed on the unwrapped value by the wrapped
type's own method, then `_wrap` runs the checks and re-wraps the
result:

```julia
function _wrap(::Type{X}, op, result, args...) where {X<:Checked}
    runchecks(X, op, result, args...)
    return X(result)
end
```

`runchecks` is a sequence of `flag && check_…(op, result, args...)`
statements whose flags are the type parameters of `X`.  Since they are
compile-time constants, the compiler deletes the disabled checks
entirely; the enabled ones inline to a comparison or two.  Each
`check_…` function dispatches on `typeof(op)`, so a check that does
not apply to the operation at hand (cancellation on `sqrt`, say) is a
no-op method that also compiles away.  A failing check calls
[`MathChecker.fail`](@ref), which is `@noinline` and invokes the
handler, so the failure path stays out of the hot loop.

Consequently, a `Checked{Float64}` with all flags off generates the
same LLVM instructions as a `Float64`, and one with the `NaN` and
`Inf` checks on adds two well-predicted branches per operation.  The
value is an immutable struct with a single field, so arrays of
`Checked` have the same memory layout as arrays of `T`.

## Operations are primitives

Every `Base` function with a `Checked` method — `hypot`, `sinpi`,
`mod`, `round`, and so on — is treated as a primitive: the wrapped
type's implementation runs unobserved, and only the final result is
checked.  Base's generic `hypot`, for instance, internally computes
essentially `1 + ϵ*ϵ` with a tiny `ϵ`, which would trip the `Swamping`
check; because `hypot` is a primitive, it does not.  The checks
therefore report on *your* arithmetic, not on the internals of the
library functions you call.

Functions that have no `Checked` method fall back to Julia's generic
implementations, which are built from the primitives and are therefore
checked step by step.  This is usually what one wants for user code,
and occasionally noisy for library code (a generic `isapprox`, say,
computes `x - y`); `isapprox` in particular is special-cased to work
on the raw values.  A full list of the primitive methods is in
`src/operations.jl`.

## Promotion

Binary operations are defined only for two `Checked` values of the
*same* type; every mixed call reaches them through Julia's promotion
machinery, so the rules live in a few `promote_rule` methods:

+ Two `Checked` values with the same `T` and different flags promote
  to the *union* of their flags (`true` beats a configured value; two
  configured tolerances take the stricter; two whitelists take their
  `Union`).  A value checked for `NaN` added to one checked for `Inf`
  is checked for both.
+ A `Checked{T}` with a plain number follows Julia's rules for `T` —
  `Checked{Float32} + Int` is a `Checked{Float32}`, `Checked{Float32}
  + Float64` is a `Checked{Float64}` — *unless* the `Precision` flag
  is set, in which case the checked value keeps its own `T` and the
  other operand must be convertible to it without loss of the check's
  guarantee.
+ Irrationals adopt the precision of the `Checked` value, as they do
  for `Float32`; Base's rules for `BigFloat` and `BigInt` are
  overridden symmetrically so that both directions of `promote_type`
  agree.

## Constructors are explicit, conversions are implicit

Julia distinguishes constructing a value (`Float64(x)`) from
converting one implicitly (`convert(Float64, x)`, which is what
promotion, `setindex!`, and typed fields use).  MathChecker leans on
this distinction:

+ **Constructors** — `Checked{T}(x)`, `Float64(x::Checked)`,
  [`checked`](@ref) — never signal and ignore the `Precision` check.
  They are how sentinels (`NaN`) are created and how the user says
  "yes, I mean it".
+ **Conversions** — `convert(::Type{<:Checked}, x)` and
  `convert(::Type{<:BaseFloat}, x::Checked)` — enforce the `Precision`
  check by dispatching, for an incompatible pair, to a function
  ([`MathChecker.mixed_precision`](@ref)) that has no matching method.

The resulting `MethodError` is a genuine dispatch failure — the same
thing JET or a type-inference report would flag — rather than an
exception thrown from inside a matched method.  An error hint
registered with `Base.Experimental.register_error_hint` (guarded as
its docstring recommends) explains the situation and the three ways
out.

## Limitations

+ **Third-party float types.**  The generic
  `(::Type{S<:AbstractFloat})(x::Checked)` constructor and the strict
  `convert` are restricted to Base's float types, because packages
  such as DoubleFloats define `(::Type{Double64})(x::Real)`
  constructors that would otherwise be ambiguous.  Converting a
  `Checked` *to* such a type therefore goes through the type's own
  constructor and is not precision-checked; converting *from* it is.
  Likewise, mixed-type methods a package defines itself (DoubleFloats'
  `<(::Double64, ::Real)`) bypass promotion and hence the check.
+ **`NaNMath` and friends.**  Packages that provide their own math
  functions with concrete-type methods (`NaNMath.sin(::Float64)`) do
  not know about `Checked`; a package extension would be needed.
+ **LAPACK.**  Anything that requires BLAS/LAPACK (`eigen`, `svd`)
  does not work for any non-BLAS float type, `Checked` included; use
  GenericLinearAlgebra or GenericSchur.
+ **Keyword constructors and inference.**  `checked(x; nan=true)`
  produces a concrete type only through constant propagation of the
  keyword *values*.  This works at ordinary call sites with literal
  flags, but in performance-critical code prefer the positional form
  `Checked{T, flags...}(x)` or construct the type once with
  `checked(T; ...)`.
