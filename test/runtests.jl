using Test
using RadioClock: decode_2digit_bcd, check_parity

encode_bcd(x) = Bool.(vcat(digits.(digits(x; base=10); base=2, pad=4)...))

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
