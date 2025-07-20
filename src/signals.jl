export DCF77

"""
    RadioSignal

Abstract type representing radio time signals.
"""
abstract type RadioSignal end

"""
    DCF77 <: RadioSignal

Type used for dispatch for functions related to the [DCF77](https://en.wikipedia.org/wiki/DCF77) time signal (e.g. [`decode(::Type{DCF77}, data::DCF77Data)`](@ref) and [`encode(::Type{DCF77}, zdt::ZonedDateTime)`](@ref)).
This struct does not hold any data, see [`DCF77Data`](@ref) for that instead.
"""
struct DCF77 <: RadioSignal end
