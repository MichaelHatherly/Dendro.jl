// Presence flags: a stub marker, a swallowed exception, and a return inside a
// finally. Three units, under the cohesion floor.

const RETRIES = 3;

function loadConfig(path) {
    // dendro-expect: stub_marker
    // TODO: validate the parsed config before returning
    return readFile(path);
}

function fetch(url) {
    for (let i = 0; i < RETRIES; i++) {
        try {
            return request(url);
            // dendro-expect: empty_catch
        } catch (e) {
        }
    }
    return null;
}

function closeQuietly(handle) {
    try {
        handle.flush();
    } finally {
        // dendro-expect: return_in_finally
        return;
    }
}
