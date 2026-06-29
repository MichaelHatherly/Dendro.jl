# `combine` uses only home's functions and none of its own file's, so its whole
# coupling lands in home: feature envy. It belongs in home.py, where its neighbourhood
# lives.
from .home import base, scale, shift


# dendro-expect: misplaced
def combine(x):
    return base(x) + scale(x) + shift(x)
