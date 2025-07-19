using LibSerialPort

function read_dcf77_data!(signal::AbstractVector{T}, port::String, rate::Signed, milliseconds::Signed) where {T<:Integer}
    N = length(signal)
    delim = "\r\n"

    open(port, rate) do sp
        # First datapoint is often incomplete, just skip it
        readuntil(sp, delim)

        @time for idx in eachindex(signal)
            data = readuntil(sp, delim)
            s = tryparse(T, data)
            @inbounds signal[idx] = isnothing(s) ? -one(T) : s
        end
    end
    return signal
end

# `millisecond` is the rate at which the data is written to the serial port, `time` is for
# how long we want to read the data, the length of the data arrays is inferred from these
# two figures.
function read_dcf77_data(port::String, rate::Signed, milliseconds::Signed, time::Real)
    N = round(Int, time / milliseconds * 1000)
    signal = zeros(Int16, N)
    return read_dcf77_data!(signal, port, rate, milliseconds)
end
