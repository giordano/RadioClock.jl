using TimeZones: FixedTimeZone, ZonedDateTime, @tz_str
using Dates: dayofweek

export DCF77Data

"""
    DCF77Data(x)

Container for [DCF77](https://en.wikipedia.org/wiki/DCF77) radio signal data.

This struct holds the raw 60-bit DCF77 signal data as a `UInt64`.
The top 4 bits must be zero, leaving 60 bits for the actual signal data.

## Fields

- `x::UInt64`: The raw signal data

## Constructors

- `DCF77Data(x::UInt64)`: Create from a 64-bit unsigned integer
- `DCF77Data(str::String)`: Create from a binary string representation

## Examples

```jldoctest
julia> using RadioClock

julia> DCF77Data(0x00a05c6908340000)
Date: 2028-02-06T08:41:00+01:00
Binary representation: 000000000000000000101100000100001001011000111010000001010000

julia> DCF77Data("000000000000000000101100000100001001011000111010000001010000")
Date: 2028-02-06T08:41:00+01:00
Binary representation: 000000000000000000101100000100001001011000111010000001010000

julia> DCF77Data("000000000000000000101100111001100011000010100100000100010010")
Date: 2022-01-10T23:39:00+01:00
Binary representation: 000000000000000000101100111001100011000010100100000100010010

julia> DCF77Data("000000000000000001001011011000000101100101011100101000000001")
Date: Invalid date
Binary representation: 000000000000000001001011011000000101100101011100101000000001
```
"""
struct DCF77Data
    x::UInt64

    function DCF77Data(x::UInt64)
        @assert iszero(x >> 60) "The top 4 bits must be zeros"
        new(x)
    end
end

DCF77Data(str::String) = DCF77Data(evalpoly(2, parse.(UInt64, collect(str))))

# 0-based indexing, to match the seconds
Base.getindex(x::DCF77Data, i::Integer) = extract_bits(x.x, i, i)

function Base.show(io::IO, x::DCF77Data)
    date = try
        decode(DCF77, x.x)
    catch
        "Invalid date"
    end
    println(io, "Date: ", date)
    print(io, "Binary representation: ", reverse(bitstring(x.x)[5:64]))
end

"""
    RadioClock.decode(DCF77, data::Union{DCF77Data,UInt64,String})

Decode [DCF77](https://en.wikipedia.org/wiki/DCF77) signal data into a `TimeZones.ZonedDateTime`.

Parses the DCF77 signal according to the official specification and returns a timezone-aware datetime object.
Performs various consistency checks to ensure data integrity.

## Arguments

- [`DCF77`](@ref): The signal type (DCF77)
- `data`: The DCF77 signal data to decode, as a [`DCF77Data`](@ref), or as a `UInt64` or a `String`, which will be automatically converted to `DCF77Data`

## Returns

- A `TimeZones.ZonedDateTime` representing the decoded time and date in the `Europe/Berlin` timezone

## Errors

Throws `AssertionError` if any validation fails, indicating corrupted or invalid signal data.

## Examples

```jldoctest
julia> using RadioClock

julia> RadioClock.decode(DCF77, DCF77Data("000000000000000001001110010100000000111001011000010001100010"))
2018-10-27T00:53:00+02:00

julia> RadioClock.decode(DCF77, "000000000000000001001101010010000011010010111111001110110010")
2037-07-12T20:15:00+02:00

julia> RadioClock.decode(DCF77, DCF77Data("000000000000000001101011000110100001100010001100011000010010"))
ERROR: AssertionError: CET/CEST data is inconsistent
[...]

julia> RadioClock.decode(DCF77, "000000000000000001001111001000100100000100001101001000110000")
ERROR: AssertionError: Date data is not consistent with parity check
[...]
```

## Notes

- Currently this assumes the year is in the 21st century (2000-2099), as the DCF77 signal is ambiguous about the century
"""
function decode(::Type{DCF77}, data::DCF77Data)
    # See:
    # * https://www.ptb.de/cms/en/ptb/fachabteilungen/abt4/fb-44/ag-442/dissemination-of-legal-time/dcf77/dcf77-time-code.html
    # * https://en.wikipedia.org/wiki/DCF77#Time_code_interpretation

    @assert iszero(data[0]) "1st bit of DCF77 signal must be 0"

    summer_time_announcement = Bool(data[15])
    cest_in_effect = Bool(data[17])
    cet_in_effect = Bool(data[18])
    # Consistency check
    @assert cest_in_effect != cet_in_effect "CET/CEST data is inconsistent"

    leap_second_announcement = data[19]

    @assert Bool(data[20]) "21st bit of DCF77 signal must be 1"

    minutes = decode_2digit_bcd(data.x, 21, 27)
    @assert parity(data.x, 21, 27) == data[28] "Minutes data is not consistent with parity check"

    hours = decode_2digit_bcd(data.x, 29, 34)
    @assert parity(data.x, 29, 34) == data[35] "Hours data is not consistent with parity check"

    day_month = decode_2digit_bcd(data.x, 36, 41)
    day_week = decode_2digit_bcd(data.x, 42, 44)
    month = decode_2digit_bcd(data.x, 45, 49)
    # NOTE: the signal reports only the year within the century, for the time being we
    # resove the ambiguity by making the strong assumption we are in the 21st century, good
    # enough until I'm alive.  TODO for future maintainers: work out the century (at least
    # within a 400-year range) from day of the week.
    year = decode_2digit_bcd(data.x, 50, 57) + 2000

    @assert parity(data.x, 36, 57) == Bool(data[58]) "Date data is not consistent with parity check"

    @assert iszero(data[59]) "Last bit must be 0"
    # Ignore leap second for the time being.

    zdt = ZonedDateTime(year, month, day_month, hours, minutes, tz"Europe/Berlin", cest_in_effect)
    # More consistency checks
    @assert dayofweek(zdt) == day_week "Day of the week data is not consistent"
    @assert FixedTimeZone(zdt) == FixedTimeZone(cet_in_effect ? "CET" : "CEST", 3600, cet_in_effect ? 0 : 3600) "CET/CEST data is not consistent with date"

    return zdt
end

decode(::Type{DCF77}, data::Union{UInt64,String}) = decode(DCF77, DCF77Data(data))
