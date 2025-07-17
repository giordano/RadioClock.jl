using LibSerialPort

function read_dcf77_data!(times::AbstractVector{Int16}, signal::AbstractVector{Int16}, port::String, rate::Signed, milliseconds::Signed)
    N = length(times)
    @assert N == length(signal) "Times and Signal vectors must have same length"
    open(port, rate) do sp
        # First datapoint is often incomplete, just skip it
        readuntil(sp, "\r\n")

        idx = 1
        while idx <= N
            data = readuntil(sp, "\r\n")
            ts = split(data, ",")
            if length(ts) != 2
                continue
            end
            t, s = tryparse.(Int16, ts)
            if any(isnothing, (t, s))
                continue
            end
            @inbounds times[idx], signal[idx] = t, s
            idx += 1
        end
    end
    return times, signal
end

# `millisecond` is the rate at which the data is written to the serial port, `time` is for
# how long we want to read the data, the length of the data arrays is inferred from these
# two figures.
function read_dcf77_data(port::String, rate::Signed, milliseconds::Signed, time::Real)
    N = round(Int, time / milliseconds * 1000)
    times  = zeros(Int16, N)
    signal = zeros(Int16, N)
    return read_dcf77_data!(times, signal, port, rate, milliseconds)
end
