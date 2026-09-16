// Fixtures for the Go half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad Go and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

package fixtures

import "strconv"

// --- banner_comment ---

// dendro-expect: banner_comment
// ========================================

// dendro-expect: banner_comment
// ----------------------------------------

// --- A rule with a title in it is a heading and stays ---

// --- boolean_return ---

func writesTheTestOut(c bool) bool {
	// dendro-expect: boolean_return
	if c {
		return true
	} else {
		return false
	}
}

func returnsTheValue(c bool, x bool) bool {
	if c {
		return true
	} else {
		return x
	}
}

// --- unreachable_branch ---

func repeatsACondition(x int) int {
	if x > 0 { // dendro-expect: unreachable_branch
		return 1
	} else if x > 0 {
		return 2
	}
	return 3
}

func testsTwoThings(x int, y int) int {
	if x > 0 {
		return 1
	} else if y > 0 {
		return 2
	}
	return 3
}

// --- manual_min_max ---

func picksTheLarger(a int, b int) int {
	// dendro-expect: manual_min_max
	if a > b {
		return a
	} else {
		return b
	}
}

func picksAFloor(a int, b int) int {
	if a > b {
		return a
	} else {
		return 0
	}
}

// --- boolean_equality ---

func comparesAFlag(flag bool) int {
	if flag == true { // dendro-expect: boolean_equality
		return 1
	}
	if false != flag { // dendro-expect: boolean_equality
		return 2
	}
	if flag {
		return 3
	}
	return 0
}

// --- redundant_conversion ---

func convertsAndBack(x int, s string) (int, string) {
	a, _ := strconv.Atoi(strconv.Itoa(x)) // dendro-expect: redundant_conversion
	b, _ := strconv.Atoi(s)
	c := strconv.Itoa(x)
	return a + b, c
}

// --- null_guard_density ---

func guardsEveryArgument(a *T, b *T, c *T) *T {
	// dendro-expect: null_guard_density
	if a == nil {
		return nil
	}
	// dendro-expect: null_guard_density
	if b == nil {
		return
	}
	// dendro-expect: null_guard_density
	if c == nil {
		return nil
	}
	return a
}

func reportsWhatWentWrong(a *T, err error) (*T, error) {
	if a == nil {
		return nil, err
	}
	return a, nil
}

func substitutesADefault(a *T, fallback *T) *T {
	if a == nil {
		return fallback
	}
	return a
}
