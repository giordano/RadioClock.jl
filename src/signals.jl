export DCF77

"""
    RadioSignal

Abstract type representing radio time signals.
"""
abstract type RadioSignal end

"""
    DCF77 <: RadioSignal

Type used for dispatch for function related to the [DCF77](https://en.wikipedia.org/wiki/DCF77) time signal.
"""
struct DCF77 <: RadioSignal end
