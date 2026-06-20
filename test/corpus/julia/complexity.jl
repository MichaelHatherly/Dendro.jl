# Scalar-metric smells, each planted well past its band so band retuning will not
# flip the fixture. The three functions share the `SCALE` const, so they form one
# component and the file is not flagged for cohesion.

const SCALE = 100

# A deeply nested classifier: high cyclomatic, cognitive, nesting, and length all at
# once. Conditions are single comparisons, so boolean complexity stays low here.
# dendro-expect: cyclomatic, cognitive_complexity, function_length, nesting_depth
function classify(grid, x, y, mode)
    score = 0
    if x > 0
        if y > 0
            if mode == 1
                if grid[1] > SCALE
                    if grid[2] > SCALE
                        if grid[3] > SCALE
                            if grid[4] > SCALE
                                score += 8
                            else
                                score += 7
                            end
                        else
                            score += 6
                        end
                    else
                        score += 5
                    end
                elseif grid[1] < SCALE
                    score += 4
                else
                    score += 3
                end
            elseif mode == 2
                score += 2
            elseif mode == 3
                score += 1
            else
                score = 0
            end
        elseif y < 0
            if mode == 1
                score -= 1
            elseif mode == 2
                score -= 2
            else
                score -= 3
            end
        else
            score = 0
        end
    elseif x < 0
        if y > 0
            if mode == 1
                score -= 4
            elseif mode == 2
                score -= 5
            elseif mode == 3
                score -= 6
            else
                score -= 7
            end
        elseif y < 0
            if mode == 1
                score -= 7
            else
                score -= 8
            end
        else
            score -= 9
        end
    else
        if y > 0
            score += 10
        elseif y < 0
            score -= 10
        else
            score = 0
        end
    end
    for k in 1:length(grid)
        if grid[k] > SCALE
            score += 1
        elseif grid[k] < 0
            score -= 1
        end
    end
    while score > SCALE
        score -= SCALE
    end
    while score < -SCALE
        score += SCALE
    end
    return score
end

# Nine parameters, past the count band.
# dendro-expect: parameter_count
function configure(a, b, c, d, e, f, g, h, i)
    return a + b + c + d + e + f + g + h + i + SCALE
end

# One boolean chain of seven operators, past the boolean band.
# dendro-expect: boolean_complexity
function eligible(a, b, c, d)
    return a > 0 && b > 0 && c > 0 && d > 0 && a < SCALE && b < SCALE && c < SCALE
end
