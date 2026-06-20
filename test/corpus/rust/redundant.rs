// Redundant-logic flags: a self comparison, an if whose arms are identical, and an
// empty body. Three units, under the cohesion floor.

const FLOOR: i32 = 0;

fn is_valid(x: i32) -> bool {
    // dendro-expect: identical_operands
    return x == x;
}

fn pick(flag: i32, a: i32, b: i32) -> i32 {
    // dendro-expect: duplicate_branches
    if flag > FLOOR {
        return a + b;
    } else {
        return a + b;
    }
}

// dendro-expect: empty_body
fn reset(state: &mut i32) {
}
