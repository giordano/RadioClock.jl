# RadioClock.jl

This is the reference documentation of [`RadioClock.jl`](https://github.com/giordano/RadioClock.jl).

## Index
```@index
```

## Time signals

### DCF77

```@docs
RadioClock.DCF77
RadioClock.DCF77Data
RadioClock.decode(::Type{DCF77}, data::DCF77Data)
```

## Internal utilities, non-public API

```@docs
RadioClock.extract_bits
RadioClock.decode_2digit_bcd
RadioClock.parity
RadioClock.RadioSignal
```
