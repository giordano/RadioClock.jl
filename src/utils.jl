function extract_bits(x::Integer, lo::Int, hi::Int)
    nbits = hi - lo + 1              # Number of bits to extract
    mask = (UInt64(1) << nbits) - 1  # Bitmask for the range
    return (x >> lo) & mask          # Shift down and mask
end

# Inspired by
# https://github.com/Ox11/dcf77/blob/413f92ad16446cbfbfd1c7bed6dc67332c1453c6/src/lib.rs#L145-L152
# Note: this assumes the input is a 2-digit BCD-encoded decimal number (∈ [0, 99]).
function decode_2digit_bcd(x::UInt64, lo::Int, hi::Int)
    bcd = extract_bits(x, lo, hi)
    high_nibble = (bcd & 0xF0) >> 4
    low_nibble = bcd & 0x0F
    return high_nibble * 10 + low_nibble
end

parity(x::Integer, lo::Int, hi::Int) = isodd(count_ones(extract_bits(x, lo, hi)))
