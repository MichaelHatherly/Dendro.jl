# Presence flags Ruby supports: a stub marker and a return inside an ensure clause.
# Ruby keeps the rescue body inline, so swallowed-rescue is not modeled. Two units,
# under the cohesion floor.

RETRIES = 3

def load_config(path)
  # dendro-expect: stub_marker
  # TODO: validate the parsed config before returning
  read_file(path)
end

def close_quietly(handle)
  begin
    flush(handle)
  ensure
    # dendro-expect: return_in_finally
    return
  end
end
