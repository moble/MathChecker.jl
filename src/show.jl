# Display.
#
# Inside a container whose element type is already known to be `Checked` (a typed array
# at the REPL, say), only the value is shown, like `Rational` and `Complex` do.  On its
# own, the type is shown so that the value is not mistaken for a plain float — using the
# short form `Checked{T}(x)` when the flags are the defaults, since that constructor
# round-trips.  `print` (and therefore string interpolation) shows just the value.

function Base.show(io::IO, x::X) where {X<:Checked}
    if get(io, :typeinfo, Any) <: Checked
        show(io, x.val)
    else
        if flags(X) === DEFAULT_FLAGS
            show(io, Checked)
            print(io, '{')
            show(io, valuetype(X))
            print(io, "}(")
        else
            show(io, X)
            print(io, '(')
        end
        show(io, x.val)
        print(io, ')')
    end
    return nothing
end

Base.print(io::IO, x::Checked) = print(io, x.val)
