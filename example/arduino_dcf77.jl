using LibSerialPort
using RadioClock
using Dates
using TimeZones

function read_dcf77_data!(signal::AbstractVector{T}, port::String, rate::Signed, milliseconds::Real; plot::Bool=false) where {T<:Integer}
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
function read_dcf77_data(port::String, rate::Signed, milliseconds::Real, time::Real; plot::Bool=false)
    N = round(Int, time / milliseconds * 1000)
    signal = zeros(Int16, N)
    return read_dcf77_data!(signal, port, rate, milliseconds; plot)
end

# `threshold` is the expected minimum height of the pulse
function read_and_decode(signal::AbstractVector{<:Integer}, milliseconds::Real; threshold::Signed=400)
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
                if max(2, zero_length * 0.3) <= pulse_count < zero_length * 1.4
                    # This is a 0 bit
                    second_done = true
                    continue
                elseif one_length * 0.7 < pulse_count < one_length * 1.2
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


"""
    decode_dcf77_stream(data_source::Function, milliseconds::Real; threshold::Signed=400, max_samples::Union{Int,Nothing}=nothing)

Generic DCF77 decoder that reads data from a provided data source function.

## Arguments
- `data_source::Function`: A function that returns the next data sample when called. Should return `nothing` when no more data is available.
- `milliseconds::Real`: The sampling interval in milliseconds (must be < 100ms)
- `threshold::Signed=400`: The minimum signal level to consider as a pulse
- `max_samples::Union{Int,Nothing}=nothing`: Maximum number of samples to read (for safety), or `nothing` for unlimited

## Returns
- A `DCF77Data` object containing the decoded 60-bit signal, or `nothing` if decoding fails

## Examples

```julia
# From serial port (using a closure)
port_reader() = begin
    data = readuntil(serial_port, "\\r\\n")
    s = tryparse(Int16, data)
    return isnothing(s) ? -1 : s
end
result = decode_dcf77_stream(port_reader, 10.0)

# From file data
signal_data = collect(reinterpret(Int16, read("signal.dat")))
file_reader = let idx = Ref(0)
    () -> begin
        idx[] += 1
        return idx[] <= length(signal_data) ? signal_data[idx[]] : nothing
    end
end
result = decode_dcf77_stream(file_reader, 10.0)
```
"""
function decode_dcf77_stream(data_source::Function, milliseconds::Real; threshold::Signed=400, max_samples::Union{Int,Nothing}=nothing)
    @assert milliseconds < 100 "The read frequency must be less than one every 100ms, found $(milliseconds)ms"

    zero_length = round(Int, 100 / milliseconds)
    one_length = round(Int, 200 / milliseconds)
    second_length = round(Int, 1000 / milliseconds)

    # When we're waiting for the beginning of the minute, we expect there to be a large
    # window of time (1.8s) during which the signal is all zeros.  This variable holds the
    # expected number of datapoints in a slightly shorter window (1.5s).
    fiftynine_window = ceil(Int, 1.5 * second_length)

    # Use a circular buffer to store recent signal values for pattern matching
    buffer_size = max(fiftynine_window + 100, 2000)  # Ensure sufficient buffer
    signal_buffer = zeros(Int16, buffer_size)

    waiting = true
    done = false
    data = UInt64(0)
    second_start = 1
    second_done = true
    second = 0
    idx = 0
    samples_read = 0

    while !done
        # Get next sample from data source
        sample = data_source()
        if isnothing(sample)
            @warn "Data source exhausted before decoding completed"
            return nothing
        end

        samples_read += 1
        if !isnothing(max_samples) && samples_read > max_samples
            @warn "Maximum samples ($max_samples) reached before decoding completed"
            return nothing
        end

        idx += 1
        buffer_idx = ((idx - 1) % buffer_size) + 1
        signal_buffer[buffer_idx] = sample

        if waiting
            if idx > fiftynine_window
                # Check if we have a long enough window of zeros followed by a pulse
                window_start = max(1, idx - fiftynine_window)
                window_samples = [signal_buffer[((i - 1) % buffer_size) + 1] for i in window_start:(idx-1)]

                if all(<=(0), window_samples) && sample > threshold
                    waiting = false
                    second_start = idx
                    now = astimezone(ZonedDateTime(Dates.now(UTC), tz"UTC"), tz"Europe/Berlin")
                    @info "Started reading DCF77 signal" now
                else
                    # We are waiting for the beginning of the signal, but didn't find it yet: keep going.
                    continue
                end
            else
                continue
            end
        end

        # Signal started, we're reading the data now. Exciting times!
        if second < 59
            if second_done && idx > second_start + 0.9 * second_length && sample > threshold
                # This is the beginning of a new second
                second_done = false
                second_start = idx
                second += 1
            end

            if !second_done && idx > second_start + 1.5 * one_length
                # Count pulses in the current second
                pulse_samples = [signal_buffer[((i - 1) % buffer_size) + 1] for i in second_start:idx]
                pulse_count = count(>(threshold), pulse_samples)

                if max(2, zero_length * 0.3) <= pulse_count < zero_length * 1.4
                    # This is a 0 bit
                    second_done = true
                    continue
                elseif one_length * 0.7 < pulse_count < one_length * 1.2
                    # This is a 1 bit
                    data |= 1 << second
                    second_done = true
                    continue
                else
                    error("Something wrong at second $(second): this bit isn't 0 nor 1 (pulse_count: $pulse_count)")
                end
            end
        end

        if second == 59 && sample > threshold
            done = true
            break
        end
    end

    return DCF77Data(data)
end

function read_and_decode(port::String, rate::Signed, milliseconds::Real, time::Real; threshold::Signed=400)
    max_samples = round(Int, time / milliseconds * 1000)
    delim = "\r\n"

    # Create a data source function that reads from the serial port
    data_source = let sp_ref = Ref{Any}(nothing)
        function()
            if isnothing(sp_ref[])
                sp_ref[] = open(port, rate)
                # First datapoint is often incomplete, just skip it
                readuntil(sp_ref[], delim)
            end

            try
                data_str = readuntil(sp_ref[], delim)
                s = tryparse(Int16, data_str)
                return isnothing(s) ? Int16(-1) : s
            catch e
                if sp_ref[] !== nothing
                    close(sp_ref[])
                    sp_ref[] = nothing
                end
                return nothing
            end
        end
    end

    try
        result = decode_dcf77_stream(data_source, milliseconds; threshold, max_samples)
        if result !== nothing
            now = astimezone(ZonedDateTime(Dates.now(UTC), tz"UTC"), tz"Europe/Berlin")
            decoded = RadioClock.decode(DCF77, result.x)
            @info "Finished decoding DCF77!" result.x decoded now (now - decoded)
        end
        return result
    finally
        # Clean up serial port connection
        if data_source isa Function
            # Try to get one more sample to trigger cleanup
            try
                data_source()
            catch
            end
        end
    end
end

"""
    decode_dcf77_from_file(filename::String, milliseconds::Real; threshold::Signed=400)

Decode DCF77 signal from a binary data file for testing purposes.

## Arguments
- `filename::String`: Path to the signal data file (typically "signal.dat")
- `milliseconds::Real`: The sampling interval in milliseconds used when the data was recorded
- `threshold::Signed=400`: The minimum signal level to consider as a pulse

## Returns
- A `DCF77Data` object containing the decoded 60-bit signal, or `nothing` if decoding fails

## Example

```julia
# Decode signal from file
result = decode_dcf77_from_file("signal.dat", 10.0)
if result !== nothing
    decoded_time = RadioClock.decode(DCF77, result.x)
    println("Decoded time: ", decoded_time)
end
```
"""
function decode_dcf77_from_file(filename::String, milliseconds::Real; threshold::Signed=400)
    if !isfile(filename)
        error("Signal file '$filename' not found")
    end

    # Read the signal data from file
    signal_data = collect(reinterpret(Int16, read(filename)))
    @info "Loaded $(length(signal_data)) samples from $filename"

    # Create a data source function that reads from the array
    file_reader = let idx = Ref(0)
        function()
            idx[] += 1
            return idx[] <= length(signal_data) ? signal_data[idx[]] : nothing
        end
    end

    # Decode using the generic decoder
    result = decode_dcf77_stream(file_reader, milliseconds; threshold)

    if result !== nothing
        decoded = RadioClock.decode(DCF77, result.x)
        @info "Successfully decoded DCF77 from file!" result.x decoded
    else
        @warn "Failed to decode DCF77 signal from file"
    end

    return result
end
