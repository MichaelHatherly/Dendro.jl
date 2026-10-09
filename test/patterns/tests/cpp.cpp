// Fixtures for the C++ half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad C++ and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

#include <stdexcept>
#include <string>
#include <vector>

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

// --- swallowed_error, try_density ---

int swallows(int (*work)()) {
    try {  // dendro-expect: try_density
        return work();
        // dendro-expect: swallowed_error
    } catch (const std::exception &e) {
        return 0;
    }
}

int catches_everything(int (*work)()) {
    try {  // dendro-expect: try_density
        return work();
    } catch (...) {
        return 0;
    }
}

int handles_the_error(int (*work)(), void (*log)(const std::exception &)) {
    try {  // dendro-expect: try_density
        return work();
    } catch (const std::exception &e) {
        log(e);
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
    if (flag) {
        return 3;
    }
    return 0;
}

// --- empty_check ---

int counts_to_find_out(const std::vector<int> &xs) {
    if (xs.size() == 0) {  // dendro-expect: empty_check
        return 1;
    }
    if (0 == xs.size()) {  // dendro-expect: empty_check
        return 2;
    }
    if (xs.size() == 1) {
        return 3;
    }
    if (xs.empty()) {
        return 4;
    }
    return 0;
}

// --- redundant_conversion ---

std::string converts_and_back(int x, const std::string &s) {
    int a = std::stoi(std::to_string(x));  // dendro-expect: redundant_conversion
    std::string b = std::to_string(std::stoi(s));  // dendro-expect: redundant_conversion
    int c = std::stoi(s);
    std::string d = std::to_string(x);
    return b + d + std::to_string(a + c);
}

// --- type_check_density ---

struct Base {
    virtual ~Base() = default;
};

struct Widget : Base {};
struct Gadget : Base {};
struct Doodad : Base {};

void checks_every_argument(Base *a, Base *b, Base *c) {
    // dendro-expect: type_check_density
    if (dynamic_cast<Widget *>(a) == nullptr) {
        throw std::invalid_argument("a");
    }
    // dendro-expect: type_check_density
    if (dynamic_cast<Gadget *>(b) == nullptr) {
        throw std::invalid_argument("b");
    }
    // dendro-expect: type_check_density
    if (dynamic_cast<Doodad *>(c) == nullptr) {
        throw std::invalid_argument("c");
    }
}

Base *asks_once(Base *a) {
    if (dynamic_cast<Widget *>(a) != nullptr) {
        return a;
    }
    return nullptr;
}

// --- null_guard_density ---

Base *guards_every_argument(Base *a, Base *b, Base *c) {
    // dendro-expect: null_guard_density
    if (a == nullptr) {
        return nullptr;
    }
    if (b == nullptr) return nullptr;  // dendro-expect: null_guard_density
    // dendro-expect: null_guard_density
    if (c == nullptr) {
        return nullptr;
    }
    return a;
}

Base *substitutes_a_default(Base *a, Base *fallback) {
    if (a == nullptr) {
        return fallback;
    }
    return a;
}
