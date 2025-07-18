using TimeZones: FixedTimeZone, ZonedDateTime, @tz_str
using Dates: dayofweek

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
    @assert check_parity(data.x, 21, 27) == data[28] "Minutes data is not consistent with parity check"

    hours = decode_2digit_bcd(data.x, 29, 34)
    @assert check_parity(data.x, 29, 34) == data[35] "Hours data is not consistent with parity check"

    day_month = decode_2digit_bcd(data.x, 36, 41)
    day_week = decode_2digit_bcd(data.x, 42, 44)
    month = decode_2digit_bcd(data.x, 45, 49)
    # NOTE: the signal reports only the year within the century, for the time being we
    # resove the ambiguity by making the strong assumption we are in the 21st century, good
    # enough until I'm alive.  TODO for future maintainers: work out the century (at least
    # within a 400-year range) from day of the week.
    year = decode_2digit_bcd(data.x, 50, 57) + 2000

    @assert check_parity(data.x, 36, 57) == Bool(data[58]) "Date data is not consistent with parity check"

    @assert iszero(data[59]) "Last bit must be 0"
    # Ignore leap second for the time being.

    zdt = ZonedDateTime(year, month, day_month, hours, minutes, tz"Europe/Berlin", cest_in_effect)
    # More consistency checks
    @assert dayofweek(zdt) == day_week "Day of the week data is not consistent"
    @assert FixedTimeZone(zdt) == FixedTimeZone(cet_in_effect ? "CET" : "CEST", 3600, cet_in_effect ? 0 : 3600) "CET/CEST data is not consistent with date"

    return zdt
end

decode(::Type{DCF77}, data::UInt64) = decode(DCF77, DCF77Data(data))
