// Fixtures for the JavaScript half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad JavaScript and lives under `test/` for that
// reason: `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

// --- banner_comment ---

// dendro-expect: banner_comment
// ========================================

// dendro-expect: banner_comment
// ----------------------------------------

// --- A rule with a title in it is a heading and stays ---

// --- boolean_return ---

function writesTheTestOut(c) {
    // dendro-expect: boolean_return
    if (c) {
        return true;
    } else {
        return false;
    }
}

function returnsTheValue(c, x) {
    if (c) {
        return true;
    } else {
        return x;
    }
}

// --- unreachable_branch ---

function repeatsACondition(x) {
    if (x > 0) {  // dendro-expect: unreachable_branch
        return 1;
    } else if (x > 0) {
        return 2;
    }
    return 3;
}

function testsTwoThings(x, y) {
    if (x > 0) {
        return 1;
    } else if (y > 0) {
        return 2;
    }
    return 3;
}

// --- manual_min_max ---

function picksTheLarger(a, b) {
    // dendro-expect: manual_min_max
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

function picksAFloor(a, b) {
    if (a > b) {
        return a;
    } else {
        return 0;
    }
}

// --- swallowed_error, try_density ---

function swallows(work) {
    try {  // dendro-expect: try_density
        return work();
        // dendro-expect: swallowed_error
    } catch (e) {
        return null;
    }
}

function handlesTheError(work, log) {
    try {  // dendro-expect: try_density
        return work();
    } catch (e) {
        log(e);
        return null;
    }
}

function failsTwoWays(a, b, log) {
    let x = 0;
    let y = 0;
    try {  // dendro-expect: try_density
        x = a();
    } catch (e) {
        log(e);
    }
    try {  // dendro-expect: try_density
        y = b();
    } catch (e) {
        log(e);
    }
    return [x, y];
}

// --- boolean_equality ---

function comparesAFlag(flag) {
    if (flag == true) {  // dendro-expect: boolean_equality
        return 1;
    }
    if (false === flag) {  // dendro-expect: boolean_equality
        return 2;
    }
    if (flag == 1) {
        return 3;
    }
    if (flag) {
        return 4;
    }
    return 0;
}

// --- empty_check ---

function countsToFindOut(xs) {
    if (xs.length === 0) {  // dendro-expect: empty_check
        return 1;
    }
    if (0 === xs.length) {  // dendro-expect: empty_check
        return 2;
    }
    if (xs.length === 1) {
        return 3;
    }
    if (xs.length) {
        return 4;
    }
    return 0;
}

// --- redundant_conversion ---

function convertsAndBack(x, s) {
    const a = parseInt(String(x));  // dendro-expect: redundant_conversion
    const b = String(parseInt(s));  // dendro-expect: redundant_conversion
    const c = parseInt(s);
    const d = String(x);
    return [a, b, c, d];
}

// --- redundant_keys ---

function asksAKeyView(o, k) {
    if (Object.keys(o).includes(k)) {  // dendro-expect: redundant_keys
        return 1;
    }
    if (Object.hasOwn(o, k)) {
        return 2;
    }
    return 0;
}

// --- empty_error_type ---

class BareError extends Error {}  // dendro-expect: empty_error_type

class CarriesAPath extends Error {
    constructor(path) {
        super(path);
        this.path = path;
    }
}

class NotAnError extends Base {}

// --- type_check_density ---

function checksEveryArgument(a, b, c) {
    // dendro-expect: type_check_density
    if (!(a instanceof Widget)) {
        throw new TypeError("a");
    }
    // dendro-expect: type_check_density
    if (!(b instanceof Gadget)) {
        throw new TypeError("b");
    }
    // dendro-expect: type_check_density
    if (!(c instanceof Doodad)) {
        throw new TypeError("c");
    }
    return [a, b, c];
}

function asksOnce(a) {
    if (a instanceof Widget) {
        return a;
    }
    return 0;
}

// --- null_guard_density ---

function guardsEveryArgument(a, b, c) {
    // dendro-expect: null_guard_density
    if (a == null) {
        return null;
    }
    if (b === null) return null;  // dendro-expect: null_guard_density
    // dendro-expect: null_guard_density
    if (c == null) {
        return;
    }
    return [a, b, c];
}

function substitutesADefault(a, fallback) {
    if (a == null) {
        return fallback;
    }
    return a;
}
