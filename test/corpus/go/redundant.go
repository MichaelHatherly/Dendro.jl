package corpus

// Redundant-logic flags: a self comparison, an if whose arms are identical, and an
// empty body. Three units, under the cohesion floor.

const FLOOR = 0

func isValid(x int) bool {
    // dendro-expect: identical_operands
    return x == x
}

func pick(flag int, a int, b int) int {
    // dendro-expect: duplicate_branches
    if flag > FLOOR {
        return a + b
    } else {
        return a + b
    }
}

// dendro-expect: empty_body
func reset(state *int) {
}
