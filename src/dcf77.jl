using TimeZones: FixedTimeZone, ZonedDateTime, @tz_str
using Dates: dayofweek

function decode(::Type{DCF77}, data::AbstractVector{Bool})
    # See:
    # * https://www.ptb.de/cms/en/ptb/fachabteilungen/abt4/fb-44/ag-442/dissemination-of-legal-time/dcf77/dcf77-time-code.html
    # * https://en.wikipedia.org/wiki/DCF77#Time_code_interpretation

    @assert !data[1] "1st bit of DCF77 signal must be 0"

    summer_time_announcement = data[17]
    cest_in_effect = data[18]
    cet_in_effect = data[19]
    # Consistency check
    @assert cest_in_effect != cet_in_effect "CET/CEST data is inconsistent"

    leap_second_announcement = data[20]

    @assert data[21] "20th bit of DCF77 signal must be 1"

    minutes = decode_2digit_bcd(@view data[22:28])
    @assert mod(count_ones(minutes), 2) == data[29] "Minutes data is not consistent with parity check"

    hours = decode_2digit_bcd(@view data[30:35])
    @assert mod(count_ones(hours), 2) == data[36] "Hours data is not consistent with parity check"

    day_month = decode_2digit_bcd(@view data[37:42])
    day_week = decode_2digit_bcd(@view data[43:45])
    month = decode_2digit_bcd(@view data[46:50])
    # NOTE: the signal reports only the year within the century, for the time being we
    # resove the ambiguity by making the strong assumption we are in the 21st century, good
    # enough until I'm alive.  TODO for future maintainers: work out the century (at least
    # within a 400-year range) from day of the week.
    year = decode_2digit_bcd(@view data[51:58]) + 2000

    @assert mod(count(@view data[37:58]), 2) == data[59] "Date data is not consistent with parity check"

    @assert !data[60] "Last bit must be 0"
    # Ignore leap second for the time being.

    zdt = ZonedDateTime(year, month, day_month, hour, minute, tz"Europe/Berlin")
    # More consistency checks
    @assert dayofweek(zdt) == day_week "Day of the week data is not consistent"
    @assert FixedTimeZone(zdt) == FixedTimeZone(cet_in_effect ? "UTC+1" : "UTC+2") "CET/CEST data is not consistent with date"

    return zdt
end
