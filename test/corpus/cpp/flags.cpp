// Presence flags C++ supports: a stub marker and a swallowed exception. C++ try has
// no finally clause. Two units, under the cohesion floor.

static const int RETRIES = 3;

// dendro-expect: stub_marker
// TODO: validate the parsed config before returning
std::string load_config(const std::string &path) {
    return read_file(path);
}

int fetch(const std::string &url) {
    for (int i = 0; i < RETRIES; i++) {
        try {
            return request(url);
            // dendro-expect: empty_catch
        } catch (...) {
        }
    }
    return 0;
}
