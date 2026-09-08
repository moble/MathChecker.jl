```@meta
CurrentModule = MathChecker
```

# The checks

A [`Checked`](@ref) has eight type parameters:

```julia
Checked{T, Precision, NaN, Inf, Cancellation, Swamping, Subnormal, Rounding}
```

`T` is the wrapped floating-point type.  Each of the remaining seven
is a *flag*: `false` turns the check off and `true` turns it on.
Three of the flags accept a configuration value in place of `true`,
described below.  The flags can be given positionally, or by keyword
to [`checked`](@ref), `Checked{T}(x; ...)`, and `Checked(x; ...)`:

```julia
Checked{Float64, true, true, true, 1e-6, false, false, false}(x)
checked(x; cancellation=1e-6)          # the same, with the other flags at their defaults
```

The defaults ([`DEFAULT_FLAGS`](@ref)) turn on `Precision`, `NaN`, and
`Inf` — the three checks that can never produce a false positive — and
leave the rest off.

Every check is *evaluated on the unwrapped values*, after the
operation has been computed by the wrapped type's own method.  A
`Checked{Float64}` therefore always computes exactly what a `Float64`
would; the checks only observe.  When a check fails it calls the
current [handler](@ref handling-failures), which by default throws.

## `Precision`

*Signals when the value is implicitly mixed with a floating-point
value of a different type.*  A `Checked{Float32}` cannot be added to a
`Float64`; a `Checked{Double64}` cannot be multiplied by a `Float64`
literal such as `0.5`.

Unlike the other checks, this one has no runtime component.  Julia's
promotion mechanism implements mixed-type arithmetic by `convert`ing
the operands to a common type, and the `Precision` check works by
making that implicit conversion a `MethodError` — a plain dispatch
failure, visible to static analyzers, that carries an explanatory
hint:

```julia-repl
julia> Checked{Float32}(1) + 0.5
ERROR: MethodError: no method matching mixed_precision(::MathChecker.PrecisionMismatch{Checked{Float32, true, true, true, false, false, false, false}, Float64}, ::Float64)
The function `mixed_precision` exists, but no method is defined for this combination of argument types.

MathChecker: the type Checked{Float32, true, true, true, false, false, false, false} has the `Precision` check enabled, which forbids implicitly mixing it with Float64.
  This usually means a `Float32` computation was contaminated by a `Float64` (a literal like `0.5`, or a value from another part of the code).
  If the mixing is intentional, convert explicitly (e.g. `Float32(x)` or `Checked{Float32}(x)`), permit the type by setting the `Precision` flag to `Float64` instead of `true` (`checked(x; precision=Float64)`), or turn the check off.
```

Mixing is always permitted with the *exact* number types, which carry
no precision of their own: `Integer` (including `Bool` and `BigInt`),
`Rational`, and `AbstractIrrational` (`π`, `ℯ`, …).  So `2x`, `x / 3`,
`x + 1//2`, and `π * x` are all fine and produce a `Checked{T}`.

Setting the flag to a `Type` instead of `true` whitelists additional
types.  Values of a whitelisted type are converted *to `T`* — the
checked value keeps its own precision:

```julia-repl
julia> d = checked(Double64(1); precision=Float64);   # allow Float64 constants

julia> typeof(d * 0.5)
Checked{Double64, Float64, true, true, false, false, false, false}
```

A `Union` whitelists several types.  A strict `Checked` (flag `true`)
always refuses a value of another float type, even one that whitelists
it, so strictness is never lost in a mixed expression.

**What is and is not caught.**  The check applies to every path that
goes through `convert` or `promote`: arithmetic and comparison
operators, `hypot`, `atan`, `fma`, `min`/`max`, array construction
(`[x, 0.5]`), and assignment into a typed array (`v::Vector{Float64};
v[i] = x`, when `x` is a strict `Checked{Float32}`).  It does *not*
apply to:

- **Explicit constructors**: `Float64(x)`, `Checked{Float64}(x)`, and
  `checked(x)` are deliberate conversions and always work.
- **Functions that never promote**, such as `copysign(x, y)` and
  `flipsign(x, y)`, which only read the sign of `y`.
- **Conversion to a third-party float type** (`Double64(x)`, or
  storing into a `Vector{Double64}`), which goes through that type's
  own `(::Type{Foo})(x::Real)` constructor.  The reverse direction — a
  `Double64` entering a `Checked{Float64}` computation — *is* caught,
  because it goes through `convert(::Type{<:Checked}, x)`.
- **Third-party mixed-type methods.**  If a package defines its own
  `<(::Foo, ::Real)`, that method is more specific than Julia's
  promotion fallback and bypasses the check (DoubleFloats does this
  for comparisons).  Arithmetic is unaffected.

## `NaN`

*Signals a [`NaNError`](@ref) when an operation produces a `NaN`, or
when a `NaN` is an operand of `<`, `<=`, `>`, `>=`, or `cmp`.*  This
turns a quiet NaN into a *signaling* one: the first operation that
produces or consumes a `NaN` throws, with a stack trace to the
culprit.

Constructing a `Checked` from `NaN` does **not** signal, so sentinel
values can be created.  The classic use is detecting reads of
uninitialized memory:

```julia
A = fill(Checked{Float64}(NaN), n)   # instead of Vector{Float64}(undef, n)
# ... fill in *some* elements ...
sum(A)                               # throws at the first element never assigned
```

The total-order predicates `==`, `isequal`, and `isless` are *not*
checked, so that `sort`, `unique`, `Dict`s, and `hash` keep working on
arrays containing sentinels.  The inspection functions `isnan`,
`isfinite`, etc. never signal.

## `Inf`

*Signals an [`InfError`](@ref) when an operation produces `+Inf` or
`-Inf`.* Constructing a `Checked` from `Inf`, `typemax`, `floatmax`,
comparisons with infinity, and `isinf` do not signal.

## `Cancellation`

*Signals a [`CancellationError`](@ref) when an addition or subtraction
— including the additive step of `fma(a, b, c)` and `muladd(a, b, c)`
— produces a result much smaller than its operands:*

```math
|a \pm b| < \mathrm{tol} \cdot \max(|a|, |b|).
```

The default tolerance (flag `true`) is `sqrt(eps(T))`, i.e. the check
fires when at least half of the significant bits cancelled.  A
`Float64` flag sets a different relative tolerance: `checked(x;
cancellation=1e-3)` fires when more than about ten bits are lost.  The
error reports the number of bits lost, also available from
[`bitslost`](@ref).

A result of exactly zero from nonzero operands (`x - x`) is the most
complete cancellation possible and *does* trigger the check.  Results
that are not finite are never flagged (they are left to the `Inf` and
`NaN` checks).

!!! note "Cancellation is a heuristic"
    The subtraction of two nearby floating-point numbers is itself
    *exact* (Sterbenz' lemma).  The danger of cancellation is that
    whatever relative error the operands already carried is magnified
    in the result, by the same factor the magnitude shrank.  This
    check therefore points at *where* accuracy may have been lost;
    whether it actually was depends on the provenance of the operands.
    Expect some false positives in code that deliberately computes
    small differences, and use a non-throwing [handler](@ref
    handling-failures) to survey them.

## `Swamping`

*Signals a [`SwampingError`](@ref) when, in an addition or subtraction
(including the additive step of `fma`/`muladd`), one operand is so
small relative to the other that it is partly or entirely lost.*

With the flag `true`, the test is exact: it fires when the result
equals the larger operand although the smaller one is nonzero — the
small operand made *no* difference.  `1.0 + 1e-20` is the canonical
example.  With a `Float64` tolerance, the check instead fires when

```math
|\text{small}| < \mathrm{tol} \cdot |\text{large}|,
```

which catches *partial* swamping, where the low-order bits of the
small operand are lost.  The error reports which operand was swamped.
Adding zero is never swamping, and results that are not finite are
never flagged.

!!! note "Double-double types rarely swamp"
    A `Double64` stores a value as an unevaluated sum of two
    `Float64`s, so `1 + 1e-300` is exactly representable and the exact
    test never fires.  Use a tolerance with such types.

## `Subnormal`

*Signals a [`SubnormalError`](@ref) when an operation produces a
subnormal (denormal) number.*  Subnormals have fewer significant bits
than normal numbers and are often dramatically slower to compute with.
Zero is not subnormal.  Constructing a `Checked` from a subnormal does
not signal.

The check uses [`MathChecker.issubnormal`](@ref), which falls back to
`false` for types that do not implement `Base.issubnormal` (`BigFloat`
and `Double64` have no subnormals in the IEEE sense).

## `Rounding`

*Signals a [`RoundingError`](@ref) when `+`, `-`, `*`, `/`, or `sqrt`
produces a result that differs from the exact mathematical result —
that is, whenever the operation rounded.*  The residual is computed
with an error-free transformation (TwoSum for `+` and `-`; `fma`-based
residuals for `*`, `/`, and `sqrt`) and reported in the error.  `T`
must support `fma`.

This is an extremely strict check: `0.1 + 0.2` fails it.  It is
intended for verifying the steps of an algorithm that are *designed*
to be exact — splitting a number into high and low parts, compensated
summation kernels, double-double building blocks — rather than for
general use.  Other operations (`exp`, `sin`, `hypot`, …) are not
checked for rounding.
