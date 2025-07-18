using Test
using RadioClock: decode_2digit_bcd

encode_bcd(x) = Bool.(vcat(digits.(digits(x; base=10); base=2, pad=4)...))

@testset "Decoding BCD" begin
    for x in 0:99
        @test decode_2digit_bcd(encode_bcd(x)) == x
    end
end
