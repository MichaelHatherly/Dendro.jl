# Scalar-metric smells, each planted well past its band. The three functions form
# a file of three units, under the cohesion floor.

SCALE = 100


# dendro-expect: cyclomatic, cognitive_complexity, function_length, nesting_depth
def classify(grid, x, y, mode):
    score = 0
    if x > 0:
        if y > 0:
            if mode == 1:
                if grid[0] > SCALE:
                    if grid[1] > SCALE:
                        if grid[2] > SCALE:
                            if grid[3] > SCALE:
                                score += 8
                            else:
                                score += 7
                        else:
                            score += 6
                    else:
                        score += 5
                elif grid[0] < SCALE:
                    score += 4
                else:
                    score += 3
            elif mode == 2:
                score += 2
            elif mode == 3:
                score += 1
            else:
                score = 0
        elif y < 0:
            if mode == 1:
                score -= 1
            elif mode == 2:
                score -= 2
            else:
                score -= 3
        else:
            score = 0
    elif x < 0:
        if y > 0:
            if mode == 1:
                score -= 4
            elif mode == 2:
                score -= 5
            elif mode == 3:
                score -= 6
            else:
                score -= 7
        elif y < 0:
            if mode == 1:
                score -= 8
            else:
                score -= 9
        else:
            score -= 10
    else:
        if y > 0:
            score += 10
        elif y < 0:
            score -= 10
        else:
            score = 0
    for k in range(len(grid)):
        if grid[k] > SCALE:
            score += 1
        elif grid[k] < 0:
            score -= 1
    while score > SCALE:
        score -= SCALE
    while score < -SCALE:
        score += SCALE
    return score


# dendro-expect: parameter_count
def configure(a, b, c, d, e, f, g, h, i):
    return a + b + c + d + e + f + g + h + i + SCALE


# dendro-expect: boolean_complexity
def eligible(a, b, c, d):
    return a > 0 and b > 0 and c > 0 and d > 0 and a < SCALE and b < SCALE and c < SCALE
