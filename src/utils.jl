# Inspired by
# https://github.com/Ox11/dcf77/blob/413f92ad16446cbfbfd1c7bed6dc67332c1453c6/src/lib.rs#L145-L152
# Note: this assumes the input is a 2-digit BCD-encoded decimal number (∈ [0, 99]).
function decode_2digit_bcd(x::Integer)
    length = ndigits(x; base=2)
    mask = 1 << length - 1
    bcd = x & mask
    high_nibble = (bcd & 0xF0) >> 4
    low_nibble = bcd & 0x0F
    return high_nibble * 10 + low_nibble
end

decode_2digit_bcd(x::AbstractVector{Bool}) =
    decode_2digit_bcd(Int(evalpoly(2, x)))

check_parity(x::AbstractVector{Bool}) = foldl(⊻, x; init=false)
