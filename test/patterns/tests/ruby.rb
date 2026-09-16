# Fixtures for the Ruby half of the pack Dendro ships.
#
# A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
# must not be, so the near-miss written beside each rule is as much of the test as the match
# is. This file is deliberately bad Ruby and lives under `test/` for that reason: `src/` is
# what the dogfood gate scans.
#
# A comment is a named node in this grammar, so a marker trailing the line a block opens on
# becomes the block's first child and a rule anchored on "the block holds nothing but this"
# stops matching. Every such rule is marked from the line above instead.

# --- banner_comment ---

# dendro-expect: banner_comment
# ========================================

# dendro-expect: banner_comment
# ----------------------------------------

# --- A rule with a title in it is a heading and stays ---

# --- boolean_return ---

def writes_the_test_out(c)
  # dendro-expect: boolean_return
  if c
    true
  else
    false
  end
end

def writes_the_test_out_with_return(c)
  # dendro-expect: boolean_return
  if c
    return true
  else
    return false
  end
end

def returns_the_value(c, x)
  if c
    true
  else
    x
  end
end

# --- unreachable_branch ---

def repeats_a_condition(x)
  if x > 0 # dendro-expect: unreachable_branch
    1
  elsif x > 0
    2
  end
end

def repeats_a_later_condition(x, y)
  if x > 0
    1
  elsif y > 0 # dendro-expect: unreachable_branch
    2
  elsif y > 0
    3
  end
end

def tests_two_things(x, y)
  if x > 0
    1
  elsif y > 0
    2
  end
end

# --- manual_min_max ---

def picks_the_larger(a, b)
  # dendro-expect: manual_min_max
  if a > b
    a
  else
    b
  end
end

def picks_the_larger_with_return(a, b)
  # dendro-expect: manual_min_max
  if a > b
    return a
  else
    return b
  end
end

def picks_a_floor(a, b)
  if a > b
    a
  else
    0
  end
end

# --- swallowed_error, try_density ---

def swallows(work)
  # dendro-expect: try_density
  begin
    work.call
    # dendro-expect: swallowed_error
  rescue StandardError => e
    return nil
  end
end

def converts_a_failure(work)
  # dendro-expect: try_density
  begin
    work.call
  rescue JSON::ParserError => e
    return nil
  end
end

def handles_the_error(work, log)
  # dendro-expect: try_density
  begin
    work.call
  rescue StandardError => e
    log.warn(e)
    return nil
  end
end

# --- boolean_equality ---

def compares_a_flag(flag)
  return 1 if flag == true # dendro-expect: boolean_equality
  return 2 if false != flag # dendro-expect: boolean_equality
  return 3 if flag
  0
end

# --- empty_check ---

def counts_to_find_out(xs)
  return 1 if xs.size == 0 # dendro-expect: empty_check
  return 2 if 0 == xs.size # dendro-expect: empty_check
  return 3 if xs.size == 1
  return 4 if xs.empty?
  0
end

# --- redundant_conversion ---

def converts_and_back(x, s)
  a = x.to_s.to_i # dendro-expect: redundant_conversion
  b = x.to_i.to_s # dendro-expect: redundant_conversion
  c = s.to_i
  d = x.to_s
  [a, b, c, d]
end

# --- redundant_keys ---

def asks_a_key_view(d, k)
  return 1 if d.keys.include?(k) # dendro-expect: redundant_keys
  return 2 if d.key?(k)
  0
end

# --- type_check_density ---

def checks_every_argument(a, b, c)
  raise ArgumentError, 'a' unless a.is_a?(Widget) # dendro-expect: type_check_density
  raise ArgumentError, 'b' unless b.is_a?(Gadget) # dendro-expect: type_check_density
  raise ArgumentError, 'c' unless c.is_a?(Doodad) # dendro-expect: type_check_density
  [a, b, c]
end

def asks_once(a)
  return a if a.is_a?(Widget)
  0
end

# --- null_guard_density ---

def guards_every_argument(a, b, c)
  return nil if a.nil? # dendro-expect: null_guard_density
  return if b.nil? # dendro-expect: null_guard_density
  # dendro-expect: null_guard_density
  if c.nil?
    return nil
  end
  [a, b, c]
end

def substitutes_a_default(a, fallback)
  return fallback if a.nil?
  a
end

# --- empty_error_type ---

# dendro-expect: empty_error_type
class BareError < StandardError; end

# dendro-expect: empty_error_type
class UnwrittenError < StandardError
end

class CarriesAPath < StandardError
  attr_reader :path

  def initialize(path)
    super(path)
    @path = path
  end
end

class NotAnError < Base; end
