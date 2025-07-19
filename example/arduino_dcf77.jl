using LibSerialPort
using RadioClock
using Plots: Plots

function read_dcf77_data!(signal::AbstractVector{T}, port::String, rate::Signed, milliseconds::Signed; plot::Bool=false) where {T<:Integer}
    N = length(signal)
    delim = "\r\n"

    open(port, rate) do sp
        # First datapoint is often incomplete, just skip it
        readuntil(sp, delim)

        @time for idx in eachindex(signal)
            data = readuntil(sp, delim)
            s = tryparse(T, data)
            @inbounds signal[idx] = isnothing(s) ? -one(T) : s
            if plot && isone(mod(idx, round(Int, 1000 / milliseconds)))
                display(Plots.plot(@view signal[begin:idx]))
            end
        end
    end
    return signal
end

# `millisecond` is the rate at which the data is written to the serial port, `time` is for
# how long we want to read the data, the length of the data arrays is inferred from these
# two figures.
function read_dcf77_data(port::String, rate::Signed, milliseconds::Signed, time::Real; plot::Bool=false)
    N = round(Int, time / milliseconds * 1000)
    signal = zeros(Int16, N)
    return read_dcf77_data!(signal, port, rate, milliseconds; plot)
end

# `threshold` is the expected minimum height of the pulse
function read_and_decode(signal::AbstractVector{<:Integer}, milliseconds::Signed; threshold::Signed=400)
    @assert milliseconds < 100 "The read frequency must be less than one every 100ms, found $(milliseconds)ms"
    zero_length = round(Int, 100 / milliseconds)
    one_length = round(Int, 200 / milliseconds)
    second_length = round(Int, 1000 / milliseconds)

    # When we're waiting for the beginning of the minute, we expect there to be a large
    # window of time (1.8s) during which the signal is all zeros.  This variable holds the
    # expected number of datapoints in a slightly shorter window (1.5s).
    fiftynine_window = ceil(Int, 1.5 * second_length)

    waiting = true
    done = false
    data = UInt64(0)
    second_start = firstindex(signal)
    second_done = true
    second = 0
    idx = 0

    # Wait for the beginning of the minute
    while !done
        idx += 1
        if waiting
            if idx > fiftynine_window && all(<=(0), @view(signal[max(begin, idx - 1 - fiftynine_window):max(begin, idx-1)])) && signal[idx] > threshold
                waiting = false
                second_start = idx
            else
                # We are waiting for the beginning of the signal, but didn't find it yet: keep going.
                continue
            end
        end

        # Signal started, we're reading the data now. Exciting times!
        if second < 59
            if second_done && idx > second_start + 0.9 * second_length && signal[idx] > threshold
                # This is the beginning of a new second
                second_done = false
                second_start = idx
                second += 1
            end

            if !second_done && idx > second_start + 1.5 * one_length
                pulse_count = count(>(threshold), @view(signal[second_start:idx]))
                if zero_length * 0.8 < pulse_count < zero_length * 1.2
                    # This is a 0 bit
                    second_done = true
                    continue
                elseif one_length * 0.8 < pulse_count < one_length * 1.2
                    # This is a 1 bit
                    data |= 1 << second
                    second_done = true
                    continue
                else
                    error("Something wrong at second $(second): this bit isn't 0 nor 1")
                end
            end

        end

        if second == 59 && signal[idx] > threshold
            done = true
            break
        end
    end

    return DCF77Data(data)
end
