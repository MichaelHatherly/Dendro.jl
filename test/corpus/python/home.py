# Home module: three helpers that form one concern, each building on the last. The
# destination an envious unit in another file should move to.
def base(x):
    return x + 1


def scale(x):
    return base(x) * 2


def shift(x):
    return scale(x) + base(x)
