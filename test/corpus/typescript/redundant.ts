// Redundant-logic flags: a self comparison, an if whose arms are identical, and an
// empty body. Three units, under the cohesion floor.

const FLOOR: number = 0;

function isValid(x: number): boolean {
    // dendro-expect: identical_operands
    return x === x;
}

function pick(flag: number, a: number, b: number): number {
    // dendro-expect: duplicate_branches
    if (flag > FLOOR) {
        return a + b;
    } else {
        return a + b;
    }
}

// dendro-expect: empty_body
function reset(state: number[]): void {
}
