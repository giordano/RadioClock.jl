# RadioClock

[![CI](https://github.com/giordano/RadioClock.jl/workflows/UnitTests/badge.svg)](https://github.com/giordano/RadioClock.jl/actions?query=workflow%3AUnitTests)
[![Coverage](https://codecov.io/gh/giordano/RadioClock.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/giordano/RadioClock.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Julia package for decoding radio time signals, specifically the DCF77 time signal broadcast from Mainflingen, Germany.

## Overview

RadioClock provides functionality to decode the DCF77 time signal, which is a longwave radio signal that broadcasts precise time and date information. This signal is used by radio-controlled clocks and can be received across most of Europe.

## Features

- **DCF77 Signal Decoding**: Decode the 60-bit DCF77 time signal format
- **Time Zone Support**: Automatic handling of CET/CEST transitions
- **Error Detection**: Comprehensive validation and error handling
- **Pretty Printing**: Human-readable output of decoded signals
- **Comprehensive Testing**: Extensive test suite with error condition coverage

## Installation

```julia
using Pkg
Pkg.add("RadioClock")
```

## Quick Start

```julia-repl
julia> using RadioClock

julia> data = DCF77Data("000000000000000001001000100100000011111010001111001010010010") # Create DCF77 data from a binary string
Date: 2025-07-17T20:48:00+02:00
Binary representation: 000000000000000001001000100100000011111010001111001010010010

julia> datetime = RadioClock.decode(DCF77, data) # Decode the time signal
2025-07-17T20:48:00+02:00
```

## API Reference

### Types

- `DCF77Data`: Represents a 60-bit DCF77 signal
- `DCF77`: Type for DCF77 signal decoding

### Functions

- `DCF77Data(x::UInt64)`: Create DCF77 data from a 64-bit integer
- `DCF77Data(str::String)`: Create DCF77 data from a binary string
- `decode(::Type{DCF77}, data::DCF77Data)`: Decode DCF77 signal to `ZonedDateTime`
- `decode(::Type{DCF77}, data::UInt64)`: Decode DCF77 signal from integer

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT "Expat" License - see the [LICENSE](LICENSE) file for details.

## References

- [DCF77 Time Code](https://www.ptb.de/cms/en/ptb/fachabteilungen/abt4/fb-44/ag-442/dissemination-of-legal-time/dcf77/dcf77-time-code.html)
- [DCF77 Wikipedia](https://en.wikipedia.org/wiki/DCF77)
- [DCF77 Decoder](https://gheja.github.io/dcf77-decoder/tools/decode_js/decode.html)
