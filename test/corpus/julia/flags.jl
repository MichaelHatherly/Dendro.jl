# Presence flags planted in plausible code: a stub marker, a swallowed exception,
# and a return inside a finally. Three functions, no shared binding, so the file
# stays under the cohesion band.

const RETRIES = 3

function load_config(path)
    # dendro-expect: stub_marker
    # TODO: validate the parsed config before returning
    return read(path, String)
end

function fetch(url)
    for _ in 1:RETRIES
        try
            return request(url)
            # dendro-expect: empty_catch
        catch
        end
    end
    return nothing
end

function close_quietly(handle)
    try
        flush(handle)
    finally
        # dendro-expect: return_in_finally
        return nothing
    end
end
