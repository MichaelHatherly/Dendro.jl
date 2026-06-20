package corpus

// Go has no exception construct, so the only presence flag that applies is the stub
// marker.

// dendro-expect: stub_marker
// TODO: validate the parsed config before returning
func loadConfig(path string) string {
    return readFile(path)
}
