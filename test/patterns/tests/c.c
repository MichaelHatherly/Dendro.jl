// Fixtures for the C half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad C and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

#include <stdbool.h>
#include <stddef.h>

// --- banner_comment ---

// dendro-expect: banner_comment
// ========================================

// dendro-expect: banner_comment
// ----------------------------------------

// --- A rule with a title in it is a heading and stays ---

// --- boolean_return ---

bool writes_the_test_out(bool c) {
    // dendro-expect: boolean_return
    if (c) {
        return true;
    } else {
        return false;
    }
}

bool returns_the_value(bool c, bool x) {
    if (c) {
        return true;
    } else {
        return x;
    }
}

// --- unreachable_branch ---

int repeats_a_condition(int x) {
    if (x > 0) {  // dendro-expect: unreachable_branch
        return 1;
    } else if (x > 0) {
        return 2;
    }
    return 3;
}

int tests_two_things(int x, int y) {
    if (x > 0) {
        return 1;
    } else if (y > 0) {
        return 2;
    }
    return 3;
}

// --- manual_min_max ---

int picks_the_larger(int a, int b) {
    // dendro-expect: manual_min_max
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

int picks_a_floor(int a, int b) {
    if (a > b) {
        return a;
    } else {
        return 0;
    }
}

// --- boolean_equality ---

int compares_a_flag(bool flag) {
    if (flag == true) {  // dendro-expect: boolean_equality
        return 1;
    }
    if (false != flag) {  // dendro-expect: boolean_equality
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

// --- null_guard_density ---

char *guards_every_argument(char *a, char *b, char *c) {
    // dendro-expect: null_guard_density
    if (a == NULL) {
        return NULL;
    }
    if (b == NULL) return NULL;  // dendro-expect: null_guard_density
    if (!c) return NULL;  // dendro-expect: null_guard_density
    return a;
}

char *substitutes_a_default(char *a, char *fallback) {
    if (a == NULL) {
        return fallback;
    }
    return a;
}
