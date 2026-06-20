// Redundant-logic flags: a self comparison, an if whose arms are identical, and an
// empty body. Three units, under the cohesion floor.

static const int FLOOR = 0;

bool is_valid(int x) {
    // dendro-expect: identical_operands
    return x == x;
}

int pick(int flag, int a, int b) {
    // dendro-expect: duplicate_branches
    if (flag > FLOOR) {
        return a + b;
    } else {
        return a + b;
    }
}

// dendro-expect: empty_body
void reset(int *state) {
}
