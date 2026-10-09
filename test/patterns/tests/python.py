"""Fixtures for the Python half of the pack Dendro ships.

A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
must not be, so the near-miss written beside each rule is as much of the test as the match
is. This file is deliberately bad Python and lives under `test/` for that reason: `src/` is
what the dogfood gate scans.
"""

# --- banner_comment ---

# dendro-expect: banner_comment
# ========================================

# dendro-expect: banner_comment
# ----------------------------------------

# --- A rule with a title in it is a heading and stays ---


# --- boolean_return ---


def writes_the_test_out(c):
    if c:  # dendro-expect: boolean_return
        return True
    else:
        return False


def returns_the_value(c, x):
    if c:
        return True
    else:
        return x


# --- unreachable_branch ---


def repeats_a_condition(x, y):
    if x > 0:  # dendro-expect: unreachable_branch
        return 1
    elif x > 0:
        return 2
    return 3


def tests_two_things(x, y):
    if x > 0:
        return 1
    elif y > 0:
        return 2
    return 3


# --- manual_min_max ---


def picks_the_larger(a, b):
    if a > b:  # dendro-expect: manual_min_max
        return a
    else:
        return b


def picks_a_floor(a, b):
    if a > b:
        return a
    else:
        return 0


# --- swallowed_error, try_density ---


def swallows(work):
    try:  # dendro-expect: try_density
        return work()
    except Exception:  # dendro-expect: swallowed_error
        return None


def swallows_a_bound_error(work):
    try:  # dendro-expect: try_density
        return work()
    except Exception as e:  # dendro-expect: swallowed_error
        return None


def catches_one_error(work):
    try:  # dendro-expect: try_density
        return work()
    except ValueError:
        return None


def handles_the_error(work, log):
    try:  # dendro-expect: try_density
        return work()
    except Exception:
        log()
        return None


def fails_two_ways(a, b):
    try:  # dendro-expect: try_density
        x = a()
    except ValueError:
        x = None
    try:  # dendro-expect: try_density
        y = b()
    except ValueError:
        y = None
    return x, y


# --- boolean_equality ---


def compares_a_flag(flag):
    if flag == True:  # dendro-expect: boolean_equality
        return 1
    if flag is False:  # dendro-expect: boolean_equality
        return 2
    if flag == 1:
        return 3
    if flag:
        return 4
    return 0


# --- empty_check ---


def counts_to_find_out(xs):
    if len(xs) == 0:  # dendro-expect: empty_check
        pass
    if 0 == len(xs):  # dendro-expect: empty_check
        pass
    if len(xs) == 1:
        pass
    if not xs:
        pass


# --- redundant_conversion ---


def converts_and_back(x, json, payload):
    a = int(float(x))  # dendro-expect: redundant_conversion
    b = str(int(x))  # dendro-expect: redundant_conversion
    c = json.loads(json.dumps(x))  # dendro-expect: redundant_conversion
    d = int(x)
    e = json.loads(payload)
    return a, b, c, d, e


# --- redundant_keys ---


def asks_a_key_view(d, k):
    if k in d.keys():  # dendro-expect: redundant_keys
        pass
    if k in d:
        pass


# --- redundant_collect ---


def materialises(d, it, f):
    a = list(map(f, it))  # dendro-expect: redundant_collect
    b = list(d.keys())  # dendro-expect: redundant_collect
    for x in list(it):  # dendro-expect: redundant_collect
        pass
    c = list(it)
    for y in it:
        pass
    return a, b, c


# --- length_index_range ---


def walks_positions(xs):
    for i in range(len(xs)):  # dendro-expect: length_index_range
        print(xs[i])
    for i in range(10):
        print(i)
    for x in xs:
        print(x)


# --- redundant_default ---


def spells_out_the_default(d, k):
    a = d.get(k, None)  # dendro-expect: redundant_default
    b = d.get(k, 0)
    c = d.get(k)
    return a, b, c


# --- empty_error_type ---


class BareError(Exception):  # dendro-expect: empty_error_type
    pass


class DocumentedError(Exception):  # dendro-expect: empty_error_type
    """Raised when nothing else fits."""


class UnwrittenError(Exception):  # dendro-expect: empty_error_type
    ...


class CarriesAPath(Exception):
    def __init__(self, path):
        super().__init__(path)
        self.path = path


class NotAnError(Base):
    pass


# --- type_equality ---


def asks_for_an_exact_type(x, y, Foo):
    if type(x) == Foo:  # dendro-expect: type_equality
        return 1
    if Foo == type(x):  # dendro-expect: type_equality
        return 2
    if type(x) == type(y):
        return 3
    if isinstance(x, Foo):
        return 4
    return 0


# --- nothing_equality ---


def compares_against_null(x):
    if x == None:  # dendro-expect: nothing_equality
        return 1
    if x != None:  # dendro-expect: nothing_equality
        return 2
    if None == x:  # dendro-expect: nothing_equality
        return 4
    if x is None:
        return 3
    return 0


# --- type_check_density ---


def checks_every_argument(a, b, c):
    if not isinstance(a, int):  # dendro-expect: type_check_density
        raise TypeError(a)
    if not isinstance(b, str):  # dendro-expect: type_check_density
        raise TypeError(b)
    if not isinstance(c, list):  # dendro-expect: type_check_density
        raise TypeError(c)
    return a, b, c


def asks_once(a):
    if isinstance(a, int):
        return a
    return 0


# --- null_guard_density ---


def guards_every_argument(a, b, c):
    if a is None:  # dendro-expect: null_guard_density
        return None
    if b is None:  # dendro-expect: null_guard_density
        return
    if c == None:  # dendro-expect: nothing_equality, null_guard_density
        return None
    return a, b, c


def substitutes_a_default(a, DEFAULT):
    if a is None:
        return DEFAULT
    return a
