#!/usr/bin/env bash
# Bash has no exception construct, so the only presence flag that applies is the
# stub marker.

load_config() {
  # dendro-expect: stub_marker
  # TODO: validate the parsed config before returning
  cat "$1"
}
