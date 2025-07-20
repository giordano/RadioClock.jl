using Test
using RadioClock: DCF77, DCF77Data, decode, decode_2digit_bcd, parity, extract_bits, RadioClock
using TimeZones: astimezone, FixedTimeZone, next_transition_instant, ZonedDateTime, @tz_str
using Dates: dayofmonth, dayofweek, Hour, hour, Minute, minute, month, now, year, UTC

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

@testset "BCD" begin
    # This function is defined only in the tests, but we want to make sure it works well,
    # because it's used below for other tests.
    @testset "Encoding" begin
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

    @testset "Decoding" begin
        for x in 0:99
            @test decode_2digit_bcd(encode_bcd(x)) == x
        end
    end
end

@testset "Parity" begin
    @test  parity(0b1)
    @test !parity(0b11)
    @test !parity(0b110110)
    @test  parity(0b1101)

    for x in UInt64(0):UInt64(99)
        @test parity(x) == isodd(count_ones(x))
    end
end

function encode_dcf77(zdt::ZonedDateTime)
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

    @testset "Decoder" begin
        # Example from https://gabor.heja.hu/blog/2020/12/12/receiving-and-decoding-the-dcf77-time-signal-with-an-atmega-attiny-avr/
        @test decode(DCF77, DCF77Data("000010100101001000101110010011000001010010001100010000010000")) == berlin(2020, 11, 12, 1, 13)

        # Various dates, independently verified at https://gheja.github.io/dcf77-decoder/tools/decode_js/decode.html
        @test decode(DCF77, "000000000000000001001110011000100010100100111111000110000000") == berlin(2006, 7, 9, 22, 33)
        @test decode(DCF77, "000000000000000001001000000000100100100011011101000010100010") == berlin(2014, 5, 31, 12, 0)
        @test decode(DCF77, "000000000000000000101010011011110100100101100010000110100000") == berlin(2016, 2, 29, 17, 32)
        @test decode(DCF77, "000000000000000011001000100010100001111001111000011001100010") == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 1)
        @test decode(DCF77, "000000000000000000101000100010100001111001111000011001100010") == ZonedDateTime(2019, 10, 27, 2, 8, tz"Europe/Berlin", 2)
        @test decode(DCF77, "000000000000000010101010000101000001011001111110000000000000") == berlin(2000, 3, 26, 1, 42)

        # Roundtrip of encoding/decoding for a large number of datetimes
        for dt in berlin(2000, 1, 11, 0, 0):Minute(13):berlin(2038, 3, 28, 1, 0)
            @test decode(DCF77, encode_dcf77(dt)) == dt
        end
    end

    @testset "Error handling" begin
        # Test DCF77Data constructor with invalid top 4 bits
        @test_throws AssertionError DCF77Data(UInt64(1) << 60)
        @test_throws AssertionError DCF77Data(UInt64(0xF) << 60)

        # Test first bit must be 0
        @test_throws AssertionError decode(DCF77, DCF77Data(UInt64(1)))

        base_data = DCF77Data("000000000000000001001000100100000011111010001111001010010010")
        # Inconsistent summer time announcement (announcement bit is set, but next hour time doesn't switch)
        inconsistent_summer_time_announcement_data = base_data.x | (UInt64(1) << 16)
        @test_throws AssertionError decode(DCF77, inconsistent_summer_time_announcement_data)

        # Inconsistent summer time announcement (announcement bit is not set, but next hour time switches)
        @test_throws AssertionError decode(DCF77, "000000000000000000101110000001000001100011111110000000110000")

        # Test CET/CEST consistency check
        # Both CET and CEST set to true (inconsistent)
        invalid_cet_cest_data = base_data.x | (UInt64(1) << 17) | (UInt64(1) << 18)
        @test_throws AssertionError decode(DCF77, invalid_cet_cest_data)

        # Both CET and CEST set to false (inconsistent)
        invalid_cet_cest2_data = base_data.x & ~(UInt64(1) << 17) & ~(UInt64(1) << 18)
        @test_throws AssertionError decode(DCF77, invalid_cet_cest2_data)

        # Test bit 20 must be 1
        invalid_bit20_data = base_data.x & ~(UInt64(1) << 20)
        @test_throws AssertionError decode(DCF77, invalid_bit20_data)

        # Test minutes parity check failure
        invalid_minutes_parity_data = base_data.x ⊻ (UInt64(1) << 28)
        @test_throws AssertionError decode(DCF77, invalid_minutes_parity_data)

        # Test hours parity check failure
        invalid_hours_parity_data = base_data.x ⊻ (UInt64(1) << 35)
        @test_throws AssertionError decode(DCF77, invalid_hours_parity_data)

        # Test date parity check failure
        invalid_date_parity_data = base_data.x ⊻ (UInt64(1) << 58)
        @test_throws AssertionError decode(DCF77, invalid_date_parity_data)

        # Test last bit must be 0
        invalid_last_bit_data = base_data.x | (UInt64(1) << 59)
        @test_throws AssertionError decode(DCF77, invalid_last_bit_data)

        # Test day of week consistency check
        invalid_day_of_week_data = base_data.x & ~(UInt64(0b111) << 42) | (UInt64(0b111) << 42)
        @test_throws AssertionError decode(DCF77, invalid_day_of_week_data)

        # Test CET/CEST consistency with date
        # Create a date that should be in CET but signal indicates CEST
        invalid_timezone_consistency_data = base_data.x & ~(UInt64(0b11111) << 45) | (UInt64(1) << 45)
        invalid_timezone_consistency_data &= ~(UInt64(1) << 17)
        invalid_timezone_consistency_data |= (UInt64(1) << 18) | (UInt64(1) << 17)
        @test_throws AssertionError decode(DCF77, invalid_timezone_consistency_data)
    end

    @testset "Pretty printing" begin
        # Test valid DCF77 data printing
        str = "000000000000000000101111001001110001111000101010000000010010"
        valid_data = DCF77Data(str)
        output = repr(valid_data)

        # Should contain "Date:" and the actual decoded date
        @test occursin("Date:", output)
        @test occursin("2020-02-07T07:27:00+01:00", output)  # Expected decoded date

        # Should contain "Binary representation:" and the binary string
        @test occursin("Binary representation:", output)
        @test occursin(str, output)

        # Test invalid DCF77 data printing
        invalid_data = DCF77Data(UInt64(1))  # Invalid: first bit is 1
        output = repr(invalid_data)

        # Should contain "Date:" and "Invalid date"
        @test occursin("Date:", output)
        @test occursin("Invalid date", output)

        # Should still contain "Binary representation:" and the binary string
        @test occursin("Binary representation:", output)
        @test occursin("100000000000000000000000000000000000000000000000000000000000", output)

        # Test another valid data with different date
        str = "000000000000000001001000100011100011111010101100101000010000"
        valid_data2 = DCF77Data(str)
        output = repr(valid_data2)

        @test occursin("Date:", output)
        @test occursin("2021-09-17T23:08:00+02:00", output)  # Expected decoded date

        @test occursin("Binary representation:", output)
        @test occursin(str, output)

        # Test that the output format is consistent
        lines = split(output, '\n')
        @test length(lines) == 2  # Should have exactly 2 lines
        @test startswith(lines[1], "Date: ")
        @test startswith(lines[2], "Binary representation: ")

        # Test edge case: data with all zeros
        zero_data = DCF77Data(UInt64(0))
        output = repr(zero_data)
        @test occursin("Date:", output)
        @test occursin("Binary representation:", output)
        @test occursin("000000000000000000000000000000000000000000000000000000000000", output)

        # Test that the binary representation is always 60 bits long
        for data in (valid_data, invalid_data, valid_data2, zero_data)
            output = repr(data)
            lines = split(output, '\n')
            binary_line = lines[2]
            binary_part = split(binary_line, ": ")[2]
            @test length(binary_part) == 60  # Should be exactly 60 bits
        end
    end

end
