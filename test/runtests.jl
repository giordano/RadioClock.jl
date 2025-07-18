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
    decode_str(T, str) = decode(T, parse.(Bool, collect(str)))
    berlin(x...) = ZonedDateTime(x..., tz"Europe/Berlin")

    # Example from https://gabor.heja.hu/blog/2020/12/12/receiving-and-decoding-the-dcf77-time-signal-with-an-atmega-attiny-avr/
    @test decode_str(DCF77, "000010100101001000101110010011000001010010001100010000010000") == berlin(2020, 11, 12, 1, 13)

    # Various dates, independently verified at https://gheja.github.io/dcf77-decoder/tools/decode_js/decode.html
    @test decode_str(DCF77, "000000000000000001001110011000100010100100111111000110000000") == berlin(2006, 7, 9, 22, 33)
    @test decode_str(DCF77, "000000000000000001001000000000100100100011011101000010100010") == berlin(2014, 5, 31, 12, 0)
    @test decode_str(DCF77, "000000000000000000101010011011110100100101100010000110100000") == berlin(2016, 2, 29, 17, 32)
    @test decode_str(DCF77, "000000000000000011001000100010100001111001111000011001100010") == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 1)
    @test decode_str(DCF77, "000000000000000000101000100010100001111001111000011001100010") == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 2)
    @test decode_str(DCF77, "000000000000000010101010000101000001011001111110000000000000") == berlin(2000, 3, 26, 1, 42)

    # Roundtrip of encoding/decoding for a large number of datetimes
    for dt in berlin(2000, 1, 11, 0, 0):Minute(23):berlin(2038, 3, 28, 1, 0)
        @test decode(DCF77, encode_dcf77(dt)) == dt
    end
end
