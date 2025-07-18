using Test
using RadioClock: DCF77, decode, decode_2digit_bcd, check_parity
using TimeZones: astimezone, FixedTimeZone, ZonedDateTime, @tz_str
using Dates: dayofmonth, dayofweek, hour, Minute, minute, month, now, year, UTC

encode_bcd(x; pad=1) = Bool.(vcat(digits.(digits(x; base=10, pad); base=2, pad=4)...))

@testset "Decoding BCD" begin
    for x in 0:99
        @test decode_2digit_bcd(encode_bcd(x)) == x
    end
end

@testset "Check parity" begin
    for x in 0:99
        v = Bool.(digits(x; base=2))
        @test check_parity(v) == (mod(count(v), 2) != 0)
    end
end

function encode_dcf77(zdt::ZonedDateTime)
    data = zeros(Bool, 60)

    day_week = dayofweek(zdt)
    tz = FixedTimeZone(zdt)
    data[18] = tz == FixedTimeZone("CEST", 3600, 3600)
    data[19] = !data[18]

    data[21] = true

    data[22:28] .= encode_bcd(minute(zdt); pad=2)[1:7]
    data[29] = check_parity(data[22:28])

    data[30:35] .= encode_bcd(hour(zdt); pad=2)[1:6]
    data[36] = check_parity(data[30:35])

    data[37:42] .= encode_bcd(dayofmonth(zdt); pad=2)[1:6]
    data[43:45] .= encode_bcd(dayofweek(zdt))[1:3]
    data[46:50] .= encode_bcd(month(zdt); pad=2)[1:5]
    data[51:58] .= encode_bcd(year(zdt); pad=2)[1:8]

    data[59] = check_parity(data[37:58])

    return data
end

function encode_dcf77(year::Integer, month::Integer, day::Integer, hour::Integer, minute::Integer)
    zdt = ZonedDateTime(year, month, day, hour, minute, tz"Europe/Berlin")
    return encode_dcf77(zdt)
end

@testset "DCF77" begin
    dt = astimezone(round(ZonedDateTime(now(UTC), tz"UTC"), Minute), tz"Europe/Berlin")
    @test decode(DCF77, encode_dcf77(dt)) == dt
end
