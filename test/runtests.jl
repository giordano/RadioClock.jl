using Test
using RadioClock: DCF77, DCF77Data, decode, decode_2digit_bcd, check_parity, extract_bits, RadioClock
using TimeZones: astimezone, FixedTimeZone, ZonedDateTime, @tz_str
using Dates: dayofmonth, dayofweek, hour, Minute, minute, month, now, year, UTC

function encode_bcd(x::Integer)
    result = UInt64(0)
    shift = UInt64(0)

    while !iszero(x)
        digit = x % 10
        result |= UInt64(digit) << shift
        x ÷= 10
        shift += 4 # Each BCD digit uses 4 bits
    end

    return result
end

# This function is defined only in the tests, but we want to make sure it works well,
# because it's used below for other tests.
@testset "Encoding BCD" begin
    @test encode_bcd(0) == 0x0
    @test encode_bcd(1) == 0x1
    @test encode_bcd(2) == 0x2
    @test encode_bcd(4) == 0x4
    @test encode_bcd(6) == 0x6
    @test encode_bcd(8) == 0x8
    @test encode_bcd(9) == 0x9
    @test encode_bcd(12) == 0x12
    @test encode_bcd(42) == 0x42
    @test encode_bcd(123) == 0x123
    @test encode_bcd(578) == 0x578
    @test encode_bcd(1234) == 0x1234
    @test encode_bcd(7654) == 0x7654
    @test encode_bcd(12345) == 0x12345
    @test encode_bcd(67890) == 0x67890
end

@testset "Decoding BCD" begin
    for x in 0:99
        @test decode_2digit_bcd(encode_bcd(x), 0, 7) == x
    end
end

@testset "Check parity" begin
    @test  check_parity(0b1,  0, 0)
    @test  check_parity(0b11, 0, 0)
    @test !check_parity(0b11, 0, 1)
    @test  check_parity(0b110110, 2, 5)

    for x in UInt64(0):UInt64(99)
        @test check_parity(x, 0, 7) == isodd(count_ones(extract_bits(x, 0, 7))) || error(x)
    end
end

function encode_dcf77(zdt::ZonedDateTime)
    data = UInt64(0)

    tz = FixedTimeZone(zdt)
    data |= (tz == FixedTimeZone("CEST", 3600, 3600)) << 17
    data |= !Bool(extract_bits(data, 17, 17)) << 18

    data |= true << 20

    data |= (encode_bcd(minute(zdt)) & 0b1111111) << 21
    data |= check_parity(data, 21, 27) << 28

    data |= (encode_bcd(hour(zdt)) & 0b111111) << 29
    data |= check_parity(data, 29, 34) << 35

    data |= (encode_bcd(dayofmonth(zdt)) & 0b111111) << 36
    data |= (encode_bcd(dayofweek(zdt)) & 0b111) << 42
    data |= (encode_bcd(month(zdt)) & 0b11111) << 45
    data |= (encode_bcd(year(zdt)) & 0b11111111) << 50

    data |= check_parity(data, 36, 57) << 58

    return DCF77Data(data)
end

function encode_dcf77(year::Integer, month::Integer, day::Integer, hour::Integer, minute::Integer)
    zdt = ZonedDateTime(year, month, day, hour, minute, tz"Europe/Berlin")
    return encode_dcf77(zdt)
end

@testset "DCF77" begin
    berlin(x...) = ZonedDateTime(x..., tz"Europe/Berlin")

    @testset "Encoder" begin
        @test encode_dcf77(berlin(2025,  7, 17, 20, 48)) == DCF77Data("000000000000000001001000100100000011111010001111001010010010")
        @test encode_dcf77(berlin(2019,  6, 16, 14, 32)) == DCF77Data("000000000000000001001010011010010100011010111011001001100010")
        @test encode_dcf77(berlin(2009,  6, 13, 10, 09)) == DCF77Data("000000000000000001001100100000000101110010011011001001000010")
        @test encode_dcf77(berlin(2000, 10,  7,  3, 59)) == DCF77Data("000000000000000001001100110101100000111000011000010000000000")
        @test encode_dcf77(berlin(2033,  2, 23, 11, 49)) == DCF77Data("000000000000000000101100100111000100110001110010001100110000")
    end

    # Example from https://gabor.heja.hu/blog/2020/12/12/receiving-and-decoding-the-dcf77-time-signal-with-an-atmega-attiny-avr/
    @test decode(DCF77, DCF77Data("000010100101001000101110010011000001010010001100010000010000")) == berlin(2020, 11, 12, 1, 13)

    # Various dates, independently verified at https://gheja.github.io/dcf77-decoder/tools/decode_js/decode.html
    @test decode(DCF77, DCF77Data("000000000000000001001110011000100010100100111111000110000000")) == berlin(2006, 7, 9, 22, 33)
    @test decode(DCF77, DCF77Data("000000000000000001001000000000100100100011011101000010100010")) == berlin(2014, 5, 31, 12, 0)
    @test decode(DCF77, DCF77Data("000000000000000000101010011011110100100101100010000110100000")) == berlin(2016, 2, 29, 17, 32)
    @test decode(DCF77, DCF77Data("000000000000000011001000100010100001111001111000011001100010")) == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 1)
    @test decode(DCF77, DCF77Data("000000000000000000101000100010100001111001111000011001100010")) == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 2)
    @test decode(DCF77, DCF77Data("000000000000000010101010000101000001011001111110000000000000")) == berlin(2000, 3, 26, 1, 42)

    # Roundtrip of encoding/decoding for a large number of datetimes
    for dt in berlin(2000, 1, 11, 0, 0):Minute(23):berlin(2038, 3, 28, 1, 0)
        @test decode(DCF77, encode_dcf77(dt)) == dt
    end
end
