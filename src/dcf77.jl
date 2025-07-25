using TimeZones: astimezone, FixedTimeZone, next_transition_instant, ZonedDateTime, @tz_str
using Dates: dayofmonth, dayofweek, Hour, hour, minute, month, year

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

# Extract bits out of `DCF77Data` using `getindex` methods.  We use 0-based
# indexing, to match the seconds.
Base.getindex(x::DCF77Data, i::Integer) = extract_bits(x.x, i, i)
Base.getindex(x::DCF77Data, I::AbstractUnitRange{<:Integer}) = extract_bits(x.x, first(I), last(I))

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
    RadioClock.decode(DCF77, data::Union{DCF77Data,UInt64,String}) :: TimeZones.ZonedDateTime

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
ERROR: AssertionError: CET/CEST data is inconsistent. Input was 0x486311858d60000
[...]

julia> RadioClock.decode(DCF77, "000000000000000001001111001000100100000100001101001000110000")
ERROR: AssertionError: Date data is not consistent with parity check. Input was 0xc4b08244f20000
[...]

julia> RadioClock.decode(DCF77, "000000000000000001001111010110100001011001111000010001000000")
ERROR: AssertionError: Summer time announcement bit (false) is not consistent with date (2008-10-26T02:57:00+02:00). Input was 0x221e685af20000
[...]
```

## Notes

- Currently this assumes the year is in the 21st century (2000-2099), as the DCF77 signal is ambiguous about the century
- The inverse of this function is [`encode(::Type{DCF77}, zdt::ZonedDateTime)`](@ref)
"""
function decode(::Type{DCF77}, data::DCF77Data)
    # See:
    # * https://www.ptb.de/cms/en/ptb/fachabteilungen/abt4/fb-44/ag-442/dissemination-of-legal-time/dcf77/dcf77-time-code.html
    # * https://en.wikipedia.org/wiki/DCF77#Time_code_interpretation

    @assert iszero(data[0]) "1st bit of DCF77 signal must be 0. Input was 0x$(string(data.x; base=16))"

    summer_time_announcement = Bool(data[16])
    cest_in_effect = Bool(data[17])
    cet_in_effect = Bool(data[18])
    # Consistency check
    @assert cest_in_effect != cet_in_effect "CET/CEST data is inconsistent. Input was 0x$(string(data.x; base=16))"

    leap_second_announcement = data[19]

    @assert Bool(data[20]) "21st bit of DCF77 signal must be 1. Input was 0x$(string(data.x; base=16))"

    minutes_data = data[21:27]
    minutes = decode_2digit_bcd(minutes_data)
    @assert parity(minutes_data) == data[28] "Minutes data is not consistent with parity check. Input was 0x$(string(data.x; base=16))"

    hours_data = data[29:34]
    hours = decode_2digit_bcd(hours_data)
    @assert parity(hours_data) == data[35] "Hours data is not consistent with parity check. Input was 0x$(string(data.x; base=16))"

    day_month = decode_2digit_bcd(data[36:41])
    day_week = decode_2digit_bcd(data[42:44])
    month = decode_2digit_bcd(data[45:49])
    # NOTE: the signal reports only the year within the century, for the time being we
    # resove the ambiguity by making the strong assumption we are in the 21st century, good
    # enough until I'm alive.  TODO for future maintainers: work out the century (at least
    # within a 400-year range) from day of the week.
    year = decode_2digit_bcd(data[50:57]) + 2000

    @assert parity(data[36:57]) == Bool(data[58]) "Date data is not consistent with parity check. Input was 0x$(string(data.x; base=16))"

    @assert iszero(data[59]) "Last bit must be 0. Input was 0x$(string(data.x; base=16))"
    # Ignore leap second for the time being.

    zdt = ZonedDateTime(year, month, day_month, hours, minutes, tz"Europe/Berlin", cest_in_effect)
    # More consistency checks
    @assert dayofweek(zdt) == day_week "Day of the week data ($(day_week)) is not consistent with date ($(zdt)). Input was 0x$(string(data.x; base=16))"
    @assert FixedTimeZone(zdt) == FixedTimeZone(cet_in_effect ? "CET" : "CEST", 3600, cet_in_effect ? 0 : 3600) "CET ($(cet_in_effect))/CEST ($(cest_in_effect)) data is not consistent with date ($(zdt)). Input was 0x$(string(data.x; base=16))"
    next_switch = next_transition_instant(zdt)
    if !isnothing(next_switch)
        @assert summer_time_announcement == (next_switch - zdt <= Hour(1)) "Summer time announcement bit ($(summer_time_announcement)) is not consistent with date ($(zdt)). Input was 0x$(string(data.x; base=16))"
    end

    return zdt
end

decode(::Type{DCF77}, data::Union{UInt64,String}) = decode(DCF77, DCF77Data(data))

"""
    RadioClock.encode(DCF77, zdt::TimeZones.ZonedDateTime) :: DCF77Data
    RadioClock.encode(DCF77, year::Integer, month::Integer, day::Integer, hour::Integer, minute::Integer) :: DCF77Data

Encode a `TimeZones.ZonedDateTime` using the [DCF77](https://en.wikipedia.org/wiki/DCF77) format.

## Arguments

- [`DCF77`](@ref): The signal type (DCF77)
- the date time in the [German time zone](https://en.wikipedia.org/wiki/Time_in_Germany) as either
  - a single `zdt::TimeZones.ZonedDateTime` object, representing the date time
  - or the sequence of the individual date time parts `year::Integer`, `month::Integer`, `day::Integer`, `hour::Integer`, `minute::Integer`

## Returns

- A [`DCF77Data`](@ref) object, holding the DCF77-like signal data

## Examples

```jldoctest
julia> using RadioClock, TimeZones

julia> RadioClock.encode(DCF77, ZonedDateTime(2014, 3, 30, 1, 18, tz"Europe/Berlin", 1))
Date: 2014-03-30T01:18:00+01:00
Binary representation: 000000000000000010101000110001000001000011111110000010100010

julia> RadioClock.encode(DCF77, 2010, 9, 2, 6, 19)
Date: 2010-09-02T06:19:00+02:00
Binary representation: 000000000000000001001100110010110000010000001100100000100010
```

## Notes

- The inverse of this function, for dates within the 21st century, is [`decode(::Type{DCF77}, data::DCF77Data)`](@ref)
"""
function encode(::Type{DCF77}, zdt::ZonedDateTime)
    zdt = astimezone(zdt, tz"Europe/Berlin")
    data = UInt64(0)

    next_switch = next_transition_instant(zdt)
    if !isnothing(next_switch)
        data |= (next_switch - zdt <= Hour(1)) << 16
    end
    tz = FixedTimeZone(zdt)
    data |= (tz == FixedTimeZone("CEST", 3600, 3600)) << 17
    data |= !Bool(extract_bits(data, 17, 17)) << 18

    data |= true << 20

    data |= (encode_bcd(minute(zdt)) & 0b1111111) << 21
    data |= parity(extract_bits(data, 21, 27)) << 28

    data |= (encode_bcd(hour(zdt)) & 0b111111) << 29
    data |= parity(extract_bits(data, 29, 34)) << 35

    data |= (encode_bcd(dayofmonth(zdt)) & 0b111111) << 36
    data |= (encode_bcd(dayofweek(zdt)) & 0b111) << 42
    data |= (encode_bcd(month(zdt)) & 0b11111) << 45
    data |= (encode_bcd(year(zdt)) & 0b11111111) << 50

    data |= parity(extract_bits(data, 36, 57)) << 58

    return DCF77Data(data)
end

function encode(::Type{DCF77}, year::Integer, month::Integer, day::Integer, hour::Integer, minute::Integer)
    zdt = ZonedDateTime(year, month, day, hour, minute, tz"Europe/Berlin")
    return encode(DCF77, zdt)
end

# Simple precompile statements
let
    precompile(decode, (Type{DCF77}, DCF77Data))
    precompile(decode, (Type{DCF77}, UInt64))
    precompile(decode, (Type{DCF77}, String))
    precompile(encode, (Type{DCF77}, ZonedDateTime))
    precompile(encode, (Type{DCF77}, Int, Int, Int, Int, Int))
end
