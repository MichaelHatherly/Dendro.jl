// Rust has no exception construct, so the only presence flag that applies is the
// stub marker.

// dendro-expect: stub_marker
// TODO: validate the parsed config before returning
fn load_config(path: &str) -> String {
    return read_file(path);
}
