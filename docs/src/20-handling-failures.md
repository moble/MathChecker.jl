```@meta
CurrentModule = MathChecker
```

# [Handling failures](@id handling-failures)

When a check fails, the operation constructs a [`CheckError`](@ref) describing what
happened and passes it to the current *handler*, a function stored in the scoped value
[`MathChecker.handler`](@ref).  The default handler is `throw`.

## The errors

Every error records the operation `op`, its unwrapped operands `args`, and the unwrapped
`result`, and prints as a readable description of the failing call:

```julia-repl
julia> checked(1.0) / 0
ERROR: InfError: 1.0 / 0.0 produced Inf.

julia> checked(1e-9; cancellation=true) + 1 - 1
ERROR: CancellationError: 1.000000001 - 1.0 produced 1.000000082740371e-9,
       cancelling 29.9 of 53 significant bits: |result| / max(|a|, |b|) = 1.0e-9
       is below the tolerance 1.49e-8 (26 bits).

julia> checked(1.0; swamping=true) + 1e-20
ERROR: SwampingError: 1.0 + 1.0e-20 produced 1.0; the operand 1.0e-20 was swamped:
       |small| / |large| = 1.0e-20, so it made no difference to the result
       (anything below ≈ 1.11e-16 would be lost).

julia> checked(0.1; rounding=true) + 0.2
ERROR: RoundingError: 0.1 + 0.2 produced 0.30000000000000004, which is inexact:
       exact − computed ≈ -2.7755575615628914e-17 (0.5 ulps).
```

| Error                        | Extra fields                       |
|:-----------------------------|:-----------------------------------|
| [`NaNError`](@ref)           |                                    |
| [`InfError`](@ref)           |                                    |
| [`SubnormalError`](@ref)     |                                    |
| [`RoundingError`](@ref)      | `residual` (exact − computed)      |
| [`CancellationError`](@ref)  | `ratio` (measured), `tolerance`; see [`bitslost`](@ref) |
| [`SwampingError`](@ref)      | `swamped` (index into `args`), `ratio`, `tolerance` |

Every message shows the operands and result in full, and the threshold checks show the
measured quantity next to the threshold it violated, in the same units.  Long messages
continue on lines indented to line up under the error name; the whole message is
available as a string from [`MathChecker.message`](@ref).

Because the error is thrown from inside the arithmetic operator, the stack trace leads
directly to the line of user code that performed the operation.

## Surveying all failures

Throwing at the first problem is right for hunting a `NaN`, but the heuristic checks are
more useful when one can see every place they fire.  [`collect_failures`](@ref) runs a
function with a recording handler and returns its result together with the list of
failures:

```julia
result, failures = collect_failures() do
    myalgorithm(checked(A; cancellation=true, swamping=true))
end
for f in failures
    println(sprint(showerror, f))
end
```

This also makes a convenient test assertion:

```julia
@test isempty(last(collect_failures(() -> myalgorithm(checked(A; cancellation=1e-3)))))
```

[`warn_handler`](@ref) instead logs each failure as a warning, with a backtrace, and lets
the computation continue:

```julia
with_handler(warn_handler) do
    myalgorithm(checked(A))
end
```

## Custom handlers

[`with_handler`](@ref)`(f, h)` calls `f()` with the handler set to any function `h` of
one argument.  If `h` returns, the operation that failed the check returns its (possibly
non-finite) result and the computation proceeds.  For example, to count failures by type:

```julia
counts = Dict{DataType,Int}()
with_handler(() -> myalgorithm(checked(A; swamping=true))) do err
    counts[typeof(err)] = get(counts, typeof(err), 0) + 1
end
```

The handler is a `ScopedValue`, so it is dynamically scoped — it applies to everything
called from `f`, however deep — and task-local, so it is safe to use different handlers on
different threads.  It can also be set directly with `ScopedValues.with`:

```julia
using ScopedValues
with(MathChecker.handler => err -> nothing) do
    ...   # ignore all failures
end
```

Custom handlers are only invoked on the *failure* path, so they add no cost to operations
whose checks pass.
