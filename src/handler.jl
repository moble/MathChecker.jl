"""
    MathChecker.handler

A `ScopedValue` holding the function that is called with a [`CheckError`](@ref) whenever a
check fails.  The default handler is `throw`.  Other handlers are free to log, record, or
ignore the error; if the handler returns, the operation that failed the check returns its
(possibly NaN, infinite, …) result as usual.

Use [`with_handler`](@ref) to change the handler for the dynamic extent of a function
call, or `ScopedValues.with(MathChecker.handler => f) do … end` directly.  Because it is
a scoped value, the setting is task-local and safe to use from multiple threads.

Provided handlers: `throw` (default), [`warn_handler`](@ref), and the collecting handler
used by [`collect_failures`](@ref).
"""
const handler = ScopedValue{Any}(throw)

"""
    MathChecker.fail(err::CheckError)

Report a failed check by calling the current [`handler`](@ref).  The checks call this
rather than `throw`, so that users can switch handlers.
"""
@noinline function fail(err::CheckError)
    handler[](err)
    return nothing
end

"""
    with_handler(f, h)

Call `f()` with [`MathChecker.handler`](@ref) set to `h` for the dynamic extent of the
call.  `h` is a function of one argument, a [`CheckError`](@ref).

```julia
with_handler(warn_handler) do
    risky_computation(checked(x))
end
```
"""
with_handler(f, h) = with(f, handler => h)

"""
    warn_handler(err::CheckError)

A [`handler`](@ref) that logs each failed check as a warning (including a backtrace to
the offending operation) and lets the computation continue.
"""
function warn_handler(err::CheckError)
    @warn sprint(showerror, err) exception = (err, backtrace())
    return nothing
end

"""
    collect_failures(f) -> (result, failures::Vector{CheckError})

Run `f()` with a [`handler`](@ref) that records every failed check instead of throwing,
and return the result of `f` together with the vector of recorded
[`CheckError`](@ref)s.  This is the recommended way to survey *all* the numerical
problems in a computation at once, or to assert that there are none:

```julia
result, failures = collect_failures() do
    myalgorithm(checked(A; cancellation=true))
end
@test isempty(failures)
```
"""
function collect_failures(f)
    failures = CheckError[]
    result = with_handler(f, err -> push!(failures, err))
    return result, failures
end
