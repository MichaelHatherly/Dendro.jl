// Fixtures for the Rust half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad Rust and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
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

fn writes_the_test_out(c: bool) -> bool {
    // dendro-expect: boolean_return
    if c {
        true
    } else {
        false
    }
}

fn writes_the_test_out_with_return(c: bool) -> bool {
    // dendro-expect: boolean_return
    if c {
        return true;
    } else {
        return false;
    }
}

fn returns_the_value(c: bool, x: bool) -> bool {
    if c {
        true
    } else {
        x
    }
}

// --- unreachable_branch ---

fn repeats_a_condition(x: i32) -> i32 {
    if x > 0 {  // dendro-expect: unreachable_branch
        1
    } else if x > 0 {
        2
    } else {
        3
    }
}

fn tests_two_things(x: i32, y: i32) -> i32 {
    if x > 0 {
        1
    } else if y > 0 {
        2
    } else {
        3
    }
}

// --- manual_min_max ---

fn picks_the_larger(a: i32, b: i32) -> i32 {
    // dendro-expect: manual_min_max
    if a > b {
        a
    } else {
        b
    }
}

fn picks_the_larger_with_return(a: i32, b: i32) -> i32 {
    // dendro-expect: manual_min_max
    if a > b {
        return a;
    } else {
        return b;
    }
}

fn picks_a_floor(a: i32, b: i32) -> i32 {
    if a > b {
        a
    } else {
        0
    }
}

// --- boolean_equality ---

fn compares_a_flag(flag: bool) -> i32 {
    if flag == true {  // dendro-expect: boolean_equality
        return 1;
    }
    if false != flag {  // dendro-expect: boolean_equality
        return 2;
    }
    if flag {
        return 3;
    }
    0
}

// --- empty_check ---

fn counts_to_find_out(xs: &[i32]) -> i32 {
    if xs.len() == 0 {  // dendro-expect: empty_check
        return 1;
    }
    if 0 == xs.len() {  // dendro-expect: empty_check
        return 2;
    }
    if xs.len() == 1 {
        return 3;
    }
    if xs.is_empty() {
        return 4;
    }
    0
}

// --- redundant_conversion ---

fn converts_and_back(x: i32, s: &str) -> i32 {
    let a: i32 = x.to_string().parse().unwrap();  // dendro-expect: redundant_conversion
    let b: i32 = s.parse().unwrap();
    let c = x.to_string();
    a + b + c.len() as i32
}

// --- length_index_range ---

fn walks_positions(v: &[i32]) -> i32 {
    let mut total = 0;
    for i in 0..v.len() {  // dendro-expect: length_index_range
        total += v[i];
    }
    for x in v {
        total += x;
    }
    total
}

// --- null_guard_density ---

fn guards_every_argument(a: Option<i32>, b: Option<i32>, c: Option<i32>) -> Option<i32> {
    // dendro-expect: null_guard_density
    if a.is_none() {
        return None;
    }
    // dendro-expect: null_guard_density
    if b.is_none() {
        return None;
    }
    // dendro-expect: null_guard_density
    if c.is_none() {
        return None;
    }
    a
}

fn substitutes_a_default(a: Option<i32>, fallback: i32) -> i32 {
    if a.is_none() {
        return fallback;
    }
    a.unwrap()
}
