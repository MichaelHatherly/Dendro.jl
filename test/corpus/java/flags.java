// Presence flags: a stub marker, a swallowed exception, and a return inside a
// finally. Three units, under the cohesion floor.

class FlagOps {
    static final int RETRIES = 3;

    String loadConfig(String path) {
        // dendro-expect: stub_marker
        // TODO: validate the parsed config before returning
        return readFile(path);
    }

    int fetch(String url) {
        for (int i = 0; i < RETRIES; i++) {
            try {
                return request(url);
                // dendro-expect: empty_catch
            } catch (Exception e) {
            }
        }
        return 0;
    }

    void closeQuietly(Handle handle) {
        try {
            handle.flush();
        } finally {
            // dendro-expect: return_in_finally
            return;
        }
    }
}
