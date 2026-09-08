# Random number generation: draw a `T` and wrap it.  Nothing to check.  (`rand` and
# `randn` are owned by Base and extended by Random; `randexp` is Random's own.)
#
# `rand(X)` for an `AbstractFloat` subtype `X` is routed by Random through the
# `CloseOpen01{X}` sampler (so defining `SamplerType{X}` would not be reached).

Base.rand(
    rng::AbstractRNG,
    ::Random.SamplerTrivial{Random.CloseOpen01{X}},
) where {X<:Checked} = X(Base.rand(rng, valuetype(X)))
Base.randn(rng::AbstractRNG, ::Type{X}) where {X<:Checked} =
    X(Base.randn(rng, valuetype(X)))
Random.randexp(rng::AbstractRNG, ::Type{X}) where {X<:Checked} =
    X(Random.randexp(rng, valuetype(X)))
