<?php

// Scalar-metric smells, each planted well past its band. Three units, under the
// cohesion floor.

const SCALE = 100;

// dendro-expect: cyclomatic, cognitive_complexity, function_length, nesting_depth
function classify($grid, $x, $y, $mode) {
    $score = 0;
    if ($x > 0) {
        if ($y > 0) {
            if ($mode == 1) {
                if ($grid[0] > SCALE) {
                    if ($grid[1] > SCALE) {
                        if ($grid[2] > SCALE) {
                            if ($grid[3] > SCALE) {
                                $score += 8;
                            } else {
                                $score += 7;
                            }
                        } else {
                            $score += 6;
                        }
                    } else {
                        $score += 5;
                    }
                } else if ($grid[0] < SCALE) {
                    $score += 4;
                } else {
                    $score += 3;
                }
            } else if ($mode == 2) {
                $score += 2;
            } else if ($mode == 3) {
                $score += 1;
            } else {
                $score = 0;
            }
        } else if ($y < 0) {
            if ($mode == 1) {
                $score -= 1;
            } else if ($mode == 2) {
                $score -= 2;
            } else {
                $score -= 3;
            }
        } else {
            $score = 0;
        }
    } else if ($x < 0) {
        if ($y > 0) {
            if ($mode == 1) {
                $score -= 4;
            } else if ($mode == 2) {
                $score -= 5;
            } else if ($mode == 3) {
                $score -= 6;
            } else {
                $score -= 7;
            }
        } else if ($y < 0) {
            if ($mode == 1) {
                $score -= 8;
            } else {
                $score -= 9;
            }
        } else {
            $score -= 10;
        }
    } else {
        $score += $y;
        $score -= $mode;
    }
    for ($k = 0; $k < 4; $k++) {
        if ($grid[$k] > SCALE) {
            $score += 1;
        } else if ($grid[$k] < 0) {
            $score -= 1;
        }
    }
    while ($score > SCALE) {
        $score -= SCALE;
    }
    while ($score < -SCALE) {
        $score += SCALE;
    }
    return $score;
}

// dendro-expect: parameter_count
function configure($a, $b, $c, $d, $e, $f, $g, $h, $i) {
    return $a + $b + $c + $d + $e + $f + $g + $h + $i + SCALE;
}

// dendro-expect: boolean_complexity
function eligible($a, $b, $c, $d) {
    return $a > 0 && $b > 0 && $c > 0 && $d > 0 && $a < SCALE && $b < SCALE && $c < SCALE;
}
