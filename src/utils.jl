"""
    extract_bits(x::Integer, lo::Int, hi::Int)

Extract a range of bits from an integer.

Extracts `hi - lo + 1` bits starting from bit position `lo` (inclusive) to bit position `hi` (inclusive).
The result is returned as an unsigned integer.

## Arguments

- `x::Integer`: The input integer to extract bits from
- `lo::Int`: The lowest bit position to extract (0-based, inclusive)
- `hi::Int`: The highest bit position to extract (0-based, inclusive)

## Returns

- An unsigned integer containing the extracted bits

## Examples

```jldoctest
julia> using RadioClock: extract_bits

julia> extract_bits(0b101010, 3, 5)
0x0000000000000005

julia> bitstring(ans)
"0000000000000000000000000000000000000000000000000000000000000101"

julia> extract_bits(0x12345678, 0, 7)
0x0000000000000078

julia> extract_bits(0x12345678, 16, 23)
0x0000000000000034
```

## Notes

- Bit positions are 0-based (least significant bit is position 0)
- The function creates a mask for the specified bit range and applies it after shifting
- Useful for parsing binary data formats
"""
function extract_bits(x::Integer, lo::Int, hi::Int)
    nbits = hi - lo + 1              # Number of bits to extract
    mask = (UInt64(1) << nbits) - 1  # Bitmask for the range
    return (x >> lo) & mask          # Shift down and mask
end

"""
    decode_2digit_bcd(x::UInt64) :: UInt64

Decode a 2-digit decimal integer encoded with the [BCD (Binary-Coded Decimal)](https://en.wikipedia.org/wiki/Binary-coded_decimal) format.

BCD encoding stores each decimal digit as a 4-bit binary number, so a 2-digit number requires 8 bits total.

## Arguments

- `x::UInt64`: The input integer containing the BCD-encoded data

## Returns

- The integer ∈ [0, 99] representing the decoded decimal value of the input number, as a `UInt64`

## Examples

```jldoctest
julia> using RadioClock: decode_2digit_bcd

julia> decode_2digit_bcd(UInt64(0x23))
0x0000000000000017

julia> Int(ans)
23
```

## Notes

- Assumes the input is a valid 2-digit BCD number in the range [0, 99]
- The high nibble (bits 4-7) represents the tens digit
- The low nibble (bits 0-3) represents the ones digit
- The inverse of this function is [`encode_bcd`](@ref)
"""
function decode_2digit_bcd(x::UInt64)
    # Inspired by
    # https://github.com/Ox11/dcf77/blob/413f92ad16446cbfbfd1c7bed6dc67332c1453c6/src/lib.rs#L145-L152
    # Note: this assumes the input is a 2-digit BCD-encoded decimal number (∈ [0, 99]).
    high_nibble = (x & 0xF0) >> 4
    low_nibble = x & 0x0F
    return high_nibble * 10 + low_nibble
end

"""
    encode_bcd(x::Integer) :: UInt64

Encode an integer using the [BCD (Binary-Coded Decimal)](https://en.wikipedia.org/wiki/Binary-coded_decimal) format.

## Arguments

- `x::Integer`: The input integer to be encoded

## Returns

- The BCD encoding of the input number as a `UInt64` number

## Examples

```jldoctest
julia> using RadioClock: encode_bcd

julia> encode_bcd(123)
0x0000000000000123

julia> encode_bcd(4296)
0x0000000000004296
```

## Notes

- The inverse of this function, for 2-digit decimal integers only, is [`decode_2digit_bcd`](@ref)
"""
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

"""
    parity(x::Integer) :: Bool

Calculate the (odd) parity for a range of bits.

Returns `true` if the number of 1-bits is odd, `false` if it's even.
This is used for error detection in data transmission.

## Arguments

- `x::Integer`: The input integer to check parity for

## Returns

- `true` if the number of 1-bits is odd
- `false` if the number of 1-bits is even

## Examples

```jldoctest
julia> using RadioClock: parity

julia> parity(0b101010)
true

julia> parity(0b011101)
false
```
"""
parity(x::Integer) = isodd(count_ones(x))
