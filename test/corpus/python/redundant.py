# Redundant-logic flags: a self comparison, an if whose arms are identical, and an
# empty body. Three units, under the cohesion floor.

FLOOR = 0


def is_valid(x):
    # dendro-expect: identical_operands
    return x == x


def pick(flag, a, b):
    # dendro-expect: duplicate_branches
    if flag > FLOOR:
        return a + b
    else:
        return a + b


# dendro-expect: empty_body
def reset(state):
    pass
