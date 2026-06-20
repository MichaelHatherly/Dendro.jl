# Presence flags: a stub marker, a swallowed exception, and a return inside a
# finally. Three units, under the cohesion floor.

RETRIES = 3


def load_config(path):
    # dendro-expect: stub_marker
    # TODO: validate the parsed config before returning
    with open(path) as fh:
        return fh.read()


def fetch(url):
    for _ in range(RETRIES):
        try:
            return request(url)
        # dendro-expect: empty_catch
        except Exception:
            pass
    return None


def close_quietly(handle):
    try:
        handle.flush()
    finally:
        # dendro-expect: return_in_finally
        return
