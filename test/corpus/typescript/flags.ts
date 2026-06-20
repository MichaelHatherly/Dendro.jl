// Presence flags: a stub marker, a swallowed exception, and a return inside a
// finally. Three units, under the cohesion floor.

const RETRIES: number = 3;

function loadConfig(path: string): string {
    // dendro-expect: stub_marker
    // TODO: validate the parsed config before returning
    return readFile(path);
}

function fetch(url: string): number {
    for (let i = 0; i < RETRIES; i++) {
        try {
            return request(url);
            // dendro-expect: empty_catch
        } catch (e) {
        }
    }
    return 0;
}

function closeQuietly(handle: Handle): void {
    try {
        handle.flush();
    } finally {
        // dendro-expect: return_in_finally
        return;
    }
}
