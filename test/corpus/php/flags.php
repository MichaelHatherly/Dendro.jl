<?php

// Presence flags: a stub marker, a swallowed exception, and a return inside a
// finally. Three units, under the cohesion floor.

const RETRIES = 3;

function load_config($path) {
    // dendro-expect: stub_marker
    // TODO: validate the parsed config before returning
    return read_file($path);
}

function fetch_url($url) {
    for ($i = 0; $i < RETRIES; $i++) {
        try {
            return request($url);
            // dendro-expect: empty_catch
        } catch (Exception $e) {
        }
    }
    return null;
}

function close_quietly($handle) {
    try {
        flush_handle($handle);
    } finally {
        // dendro-expect: return_in_finally
        return;
    }
}
