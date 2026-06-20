// C has no exception construct, so the only presence flag that applies is the stub
// marker.

// dendro-expect: stub_marker
// TODO: validate the parsed config before returning
char *load_config(const char *path) {
    return read_file(path);
}
