# Redundant-logic flags Ruby supports: a self comparison and an empty body. Ruby
# keeps if-branch bodies inline rather than in a block node, so identical-branch
# detection does not fit the block model. Two units, under the cohesion floor.

def is_valid(x)
  # dendro-expect: identical_operands
  x == x
end

# dendro-expect: empty_body
def reset(state)
end
