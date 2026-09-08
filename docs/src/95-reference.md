```@meta
CurrentModule = MathChecker
```

# [Reference](@id reference)

## Contents

```@contents
Pages = ["95-reference.md"]
Depth = 2:3
```

## The type

```@docs
MathChecker
Checked
checked
unchecked
flags
valuetype
DEFAULT_FLAGS
```

## Errors

```@docs
CheckError
NaNError
InfError
SubnormalError
RoundingError
CancellationError
AbsorptionError
bitslost
```

## Handlers

```@docs
handler
with_handler
warn_handler
collect_failures
MathChecker.fail
```

## Internals

```@docs
MathChecker.runchecks
MathChecker.issubnormal
MathChecker.hasprecision
MathChecker.PrecisionMismatch
MathChecker.mixed_precision
MathChecker.formatcall
MathChecker.message
```

## Index

```@index
Pages = ["95-reference.md"]
```
